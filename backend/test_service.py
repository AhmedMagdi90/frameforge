import asyncio
import base64
import io
import json
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import unittest
from urllib.parse import parse_qs, urlencode, urlparse
import wave
from cryptography.hazmat.primitives.asymmetric import rsa
import httpx
import jwt
from PIL import Image
from .app import create_app
from .jobs import Jobs
from .models import GenerationRequest, PlanRequest, VideoPlan
from .openai_client import ISSUER, OpenAIContent, OpenAIIdentity, ServiceError
from .render import Renderer
from .settings import Settings
from .store import Store, challenge, digest

def sample_plan(ratio='portrait'):
    return VideoPlan(title='Morning coffee', summary='A gentle start to the day.', ratio=ratio, scenes=[{'image_prompt': 'Warm morning light in a small coffee shop', 'narration': 'A new day begins.', 'caption': 'A new day', 'seconds': 2}, {'image_prompt': 'A steaming coffee cup on a wooden counter', 'narration': 'Make it your own.', 'caption': 'Your morning', 'seconds': 2}])

def synthetic_image():
    buffer = io.BytesIO()
    Image.new('RGB', (320, 480), '#ab8bdd').save(buffer, 'PNG')
    return buffer.getvalue()

def synthetic_voice():
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(24000)
        output.writeframes(b'\x00\x00' * 12000)
    return buffer.getvalue()

class FakeContent:

    async def plan(self, request):
        return sample_plan(request.ratio)

    async def image(self, prompt, ratio):
        return synthetic_image()

    async def speech(self, text, voice):
        return synthetic_voice()

class SlowContent(FakeContent):

    async def image(self, prompt, ratio):
        await asyncio.Event().wait()

class FakeIdentity:

    async def authorize_url(self, transaction):
        return ISSUER + '/authorize?' + urlencode({'state': transaction['state']})

    async def identity_for_code(self, code, transaction):
        if code != 'valid-code':
            raise ServiceError('Sign-in failed')
        return {'id': 'user-a', 'name': 'Test user', 'email': None}

class StoreTests(unittest.TestCase):

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.temp.name))
        self.user = {'id': 'owner-a', 'name': 'A', 'email': None}
        self.verifier = secrets.token_urlsafe(48)

    def tearDown(self):
        self.temp.cleanup()

    def test_ticket_pkce_replay_and_hashed_session(self):
        ticket = self.store.new_ticket(self.user, challenge(self.verifier))
        with self.assertRaises(ValueError):
            self.store.exchange_ticket(ticket, 'x' * 64, 60)
        token, user = self.store.exchange_ticket(ticket, self.verifier, 60)
        self.assertEqual(user, self.user)
        self.assertEqual(self.store.session(token), self.user)
        with self.assertRaises(ValueError):
            self.store.exchange_ticket(ticket, self.verifier, 60)
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT id FROM sessions').fetchone()[0], digest(token))
        self.assertNotIn(token.encode(), self.store.path.read_bytes())
        self.store.logout(token)
        self.assertIsNone(self.store.session(token))

    def test_expired_ticket_and_session(self):
        ticket = self.store.new_ticket(self.user, challenge(self.verifier))
        with self.store.connect() as db:
            db.execute('UPDATE tickets SET expires=0')
        with self.assertRaises(ValueError):
            self.store.exchange_ticket(ticket, self.verifier, 60)
        ticket = self.store.new_ticket(self.user, challenge(self.verifier))
        token, _ = self.store.exchange_ticket(ticket, self.verifier, -1)
        self.assertIsNone(self.store.session(token))

    def test_browser_state_bound_and_consumed(self):
        transaction = self.store.new_transaction(challenge(self.verifier), 'device-state')
        with self.assertRaises(ValueError):
            self.store.take_transaction(transaction['id'], 'wrong-state')
        with self.assertRaises(ValueError):
            self.store.take_transaction(transaction['id'], transaction['state'])
        transaction = self.store.new_transaction(challenge(self.verifier), 'device-state')
        with self.store.connect() as db:
            db.execute('UPDATE transactions SET expires=0')
        with self.assertRaises(ValueError):
            self.store.take_transaction(transaction['id'], transaction['state'])

    def test_owner_isolation_idempotency_and_daily_limit(self):
        payload = GenerationRequest(plan=sample_plan(), request_key='a' * 32).model_dump()
        job, created = self.store.new_job('a', 'a' * 32, payload, 1)
        self.assertTrue(created)
        same, created = self.store.new_job('a', 'a' * 32, payload, 1)
        self.assertFalse(created)
        self.assertEqual(job['id'], same['id'])
        self.assertIsNone(self.store.job(job['id'], 'b'))
        self.assertEqual(self.store.jobs('b'), [])
        with self.assertRaises(ValueError):
            self.store.new_job('a', 'a' * 32, payload | {'voice': 'alloy'}, 1)
        with self.assertRaises(ValueError):
            self.store.new_job('a', 'b' * 32, payload, 1)

    def test_active_limit_cancellation_and_restart_recovery(self):
        payload = GenerationRequest(plan=sample_plan(), request_key='a' * 32).model_dump()
        first, _ = self.store.new_job('a', 'a' * 32, payload, 10)
        second, _ = self.store.new_job('a', 'b' * 32, payload, 10)
        with self.assertRaises(ValueError):
            self.store.new_job('a', 'c' * 32, payload, 10)
        self.store.update_job(first['id'], status='cancelled')
        self.store.update_job(first['id'], status='completed')
        self.assertEqual(self.store.job(first['id'], 'a')['status'], 'cancelled')
        self.store.recover_jobs()
        self.assertEqual(self.store.job(second['id'], 'a')['status'], 'failed')

    def test_plan_quota_is_per_account(self):
        self.store.reserve_plan('a', 1)
        with self.assertRaises(ValueError):
            self.store.reserve_plan('a', 1)
        self.store.reserve_plan('b', 1)

class IdentityTests(unittest.IsolatedAsyncioTestCase):

    async def asyncSetUp(self):
        self.private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        key = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(self.private.public_key())) | {'kid': 'test-key', 'use': 'sig'}
        self.discovery = {'issuer': ISSUER, 'authorization_endpoint': ISSUER + '/api/accounts/authorize', 'token_endpoint': ISSUER + '/api/accounts/oauth/token', 'jwks_uri': ISSUER + '/.well-known/jwks.json'}
        self.http = httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, json=self.discovery if request.url.path.endswith('openid-configuration') else {'keys': [key]})))
        self.identity = OpenAIIdentity(Settings(client_id='oaiapp_test'), self.http)
        self.claims = {'iss': ISSUER, 'aud': 'oaiapp_test', 'sub': 'stable-user', 'nonce': 'nonce-test', 'iat': int(time.time()), 'exp': int(time.time()) + 300, 'name': 'Ada', 'email': 'ada@example.com', 'email_verified': True}

    async def asyncTearDown(self):
        await self.http.aclose()

    def token(self, changes=None):
        return jwt.encode(self.claims | (changes or {}), self.private, algorithm='RS256', headers={'kid': 'test-key'})

    async def test_signature_and_stable_subject_verified(self):
        user = await self.identity.verify_id_token(self.token(), 'nonce-test')
        self.assertEqual(user['id'], digest(ISSUER + '|stable-user'))
        self.assertEqual(user['email'], 'ada@example.com')
        unverified = await self.identity.verify_id_token(self.token({'email_verified': False}), 'nonce-test')
        self.assertIsNone(unverified['email'])

    async def test_wrong_issuer_audience_nonce_expiry_rejected(self):
        for changes in [{'iss': 'https://attacker.example'}, {'aud': 'other'}, {'nonce': 'wrong'}, {'exp': int(time.time()) - 100}, {'iat': int(time.time()) + 100}]:
            with self.subTest(changes=changes), self.assertRaises(ServiceError):
                await self.identity.verify_id_token(self.token(changes), 'nonce-test')

    async def test_wrong_signature_and_algorithm_rejected(self):
        wrong = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        token = jwt.encode(self.claims, wrong, algorithm='RS256', headers={'kid': 'test-key'})
        with self.assertRaises(ServiceError):
            await self.identity.verify_id_token(token, 'nonce-test')
        token = jwt.encode(self.claims, 'secret' * 8, algorithm='HS256', headers={'kid': 'test-key'})
        with self.assertRaises(ServiceError):
            await self.identity.verify_id_token(token, 'nonce-test')

    async def test_multiple_audience_requires_authorized_party(self):
        with self.assertRaises(ServiceError):
            await self.identity.verify_id_token(self.token({'aud': ['oaiapp_test', 'other']}), 'nonce-test')
        user = await self.identity.verify_id_token(self.token({'aud': ['oaiapp_test', 'other'], 'azp': 'oaiapp_test'}), 'nonce-test')
        self.assertEqual(user['name'], 'Ada')
        with self.assertRaises(ServiceError):
            await self.identity.verify_id_token(self.token({'azp': 'wrong-client'}), 'nonce-test')

    async def test_code_exchange_uses_registered_callback_and_verifier(self):
        observed = []
        async def respond(request):
            observed.append(request)
            return httpx.Response(200, json={'id_token': self.token()})
        self.identity._configuration = self.discovery
        self.identity._keys = await self.identity._jwks()
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
            self.identity.http = http
            user = await self.identity.identity_for_code('provider-code', {'verifier': 'v' * 64, 'nonce': 'nonce-test'})
        self.assertEqual(user['name'], 'Ada')
        form = parse_qs(observed[0].content.decode())
        self.assertEqual(form['code_verifier'], ['v' * 64])
        self.assertEqual(form['redirect_uri'], [self.identity.settings.callback_url])
        self.assertEqual(str(observed[0].url), self.discovery['token_endpoint'])

    async def test_authorize_uses_pkce_nonce_and_identity_scopes(self):
        transaction = {'state': 'state', 'nonce': 'nonce', 'verifier': 'v' * 64}
        query = parse_qs(urlparse(await self.identity.authorize_url(transaction)).query)
        self.assertEqual(query['code_challenge'], [challenge(transaction['verifier'])])
        self.assertEqual(query['scope'], ['openid profile email'])
        self.assertEqual(query['nonce'], ['nonce'])

    async def test_untrusted_discovery_endpoint_rejected(self):
        self.discovery['token_endpoint'] = 'https://attacker.example/token'
        with self.assertRaises(ServiceError):
            await self.identity.configuration()

class ProviderTests(unittest.IsolatedAsyncioTestCase):

    async def test_content_requests_use_api_key_and_expected_payloads(self):
        requests = []

        def respond(request):
            requests.append(request)
            if request.url.path.endswith('/responses'):
                return httpx.Response(200, json={'status': 'completed', 'output': [{'content': [{'type': 'output_text', 'text': sample_plan('square').model_dump_json()}]}]})
            if request.url.path.endswith('/images/generations'):
                return httpx.Response(200, json={'data': [{'b64_json': base64.b64encode(synthetic_image()).decode()}]})
            return httpx.Response(200, content=synthetic_voice())
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
            content = OpenAIContent(Settings(api_key='fake-secret'), http)
            plan = await content.plan(PlanRequest(messages=[{'role': 'user', 'content': 'A coffee video'}], ratio='portrait'))
            self.assertEqual(plan.ratio, 'portrait')
            self.assertTrue((await content.image('A coffee cup', 'portrait')).startswith(b'\x89PNG'))
            self.assertTrue((await content.speech('Hello', 'coral')).startswith(b'RIFF'))
        for request in requests:
            self.assertEqual(request.headers['authorization'], 'Bearer fake-secret')
            self.assertEqual(request.url.host, 'api.openai.com')
        self.assertFalse(json.loads(requests[0].content)['store'])
        self.assertEqual(json.loads(requests[1].content)['size'], '1024x1536')
        self.assertEqual(json.loads(requests[2].content)['response_format'], 'wav')

    async def test_provider_errors_do_not_leak_secrets_or_response_bodies(self):
        for status in [401, 403, 429, 500]:
            async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(status, text='fake-secret sensitive'))) as http:
                with self.assertRaises(ServiceError) as result:
                    await OpenAIContent(Settings(api_key='fake-secret'), http).speech('Hello', 'coral')
                self.assertNotIn('fake-secret', str(result.exception))
                self.assertNotIn('sensitive', str(result.exception))

    async def test_invalid_assets_and_incomplete_plan_rejected(self):
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, json={'data': [{'b64_json': 'invalid!'}]}))) as http:
            content = OpenAIContent(Settings(api_key='fake'), http)
            with self.assertRaises(ServiceError):
                await content.image('A coffee cup', 'square')
            with self.assertRaises(ServiceError):
                await content.speech('Hello', 'coral')
            with self.assertRaises(ServiceError):
                await content.plan(PlanRequest(messages=[{'role': 'user', 'content': 'Hello'}]))

class ApiTests(unittest.IsolatedAsyncioTestCase):

    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(data_dir=Path(self.temp.name), client_id='oaiapp_test', api_key='fake', hourly_plans=1)
        self.app = create_app(self.settings, content=SlowContent(), identity=FakeIdentity())
        self.lifespan = self.app.router.lifespan_context(self.app)
        await self.lifespan.__aenter__()
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app), base_url='http://testserver')
        self.verifier = secrets.token_urlsafe(48)
        self.headers = await self.login('user-a')

    async def login(self, owner):
        ticket = self.app.state.store.new_ticket({'id': owner, 'name': owner, 'email': None}, challenge(self.verifier))
        response = await self.client.post('/api/session/exchange', json={'code': ticket, 'verifier': self.verifier})
        self.assertEqual(response.status_code, 200)
        return {'Authorization': 'Bearer ' + response.json()['token']}

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.lifespan.__aexit__(None, None, None)
        self.temp.cleanup()

    async def test_browser_oauth_callback_and_mobile_exchange(self):
        device_state = secrets.token_urlsafe(32)
        start = await self.client.get('/auth/openai/start', params={'device_challenge': challenge(self.verifier), 'device_state': device_state}, follow_redirects=False)
        self.assertEqual(start.status_code, 303)
        self.assertIn('HttpOnly', start.headers['set-cookie'])
        state = parse_qs(urlparse(start.headers['location']).query)['state'][0]
        callback = await self.client.get('/auth/openai/callback', params={'state': state, 'code': 'valid-code'}, follow_redirects=False)
        url = urlparse(callback.headers['location'])
        query = parse_qs(url.query)
        self.assertEqual(url.scheme, 'frameforge-ai')
        self.assertEqual(query['state'], [device_state])
        exchanged = await self.client.post('/api/session/exchange', json={'code': query['code'][0], 'verifier': self.verifier})
        self.assertEqual(exchanged.status_code, 200)
        replay = await self.client.post('/api/session/exchange', json={'code': query['code'][0], 'verifier': self.verifier})
        self.assertEqual(replay.status_code, 400)

    async def test_wrong_callback_cookie_and_state_rejected(self):
        self.assertEqual((await self.client.get('/auth/openai/callback?state=wrong&code=valid-code')).status_code, 400)

    async def test_authentication_quotas_and_logout(self):
        self.assertEqual((await self.client.get('/api/jobs')).status_code, 401)
        request = {'messages': [{'role': 'user', 'content': 'Coffee video'}]}
        self.assertEqual((await self.client.post('/api/ideas/plan', json=request, headers=self.headers)).status_code, 200)
        self.assertEqual((await self.client.post('/api/ideas/plan', json=request, headers=self.headers)).status_code, 429)
        self.assertEqual((await self.client.delete('/api/session', headers=self.headers)).status_code, 200)
        self.assertEqual((await self.client.get('/api/session', headers=self.headers)).status_code, 401)

    async def test_job_idempotency_ownership_and_cancellation(self):
        payload = GenerationRequest(plan=sample_plan(), request_key='k' * 32).model_dump()
        first = await self.client.post('/api/jobs', json=payload, headers=self.headers)
        self.assertEqual(first.status_code, 202)
        job_id = first.json()['id']
        second = await self.client.post('/api/jobs', json=payload, headers=self.headers)
        self.assertEqual(second.json()['id'], job_id)
        other = await self.login('user-b')
        for path in [f'/api/jobs/{job_id}', f'/api/jobs/{job_id}/assets/video.mp4']:
            self.assertEqual((await self.client.get(path, headers=other)).status_code, 404)
        self.assertEqual((await self.client.delete(f'/api/jobs/{job_id}', headers=other)).status_code, 404)
        self.assertEqual((await self.client.get(f'/api/jobs/{job_id}/assets/video.mp4', headers=self.headers)).status_code, 409)
        result = await self.client.delete(f'/api/jobs/{job_id}', headers=self.headers)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()['status'], 'cancelled')
        self.assertFalse((self.settings.data_dir / 'jobs' / job_id).exists())

    async def test_asset_whitelist_and_security_headers(self):
        job, _ = self.app.state.store.new_job('user-a', 'k' * 32, GenerationRequest(plan=sample_plan(), request_key='k' * 32).model_dump(), 10)
        directory = self.settings.data_dir / 'jobs' / job['id']
        directory.mkdir(parents=True)
        (directory / 'video.mp4').write_bytes(b'video-fixture')
        self.app.state.store.update_job(job['id'], status='completed', manifest={'scenes': [{'filename': 'scene01.mp4'}]})
        result = await self.client.get(f"/api/jobs/{job['id']}/assets/video.mp4", headers=self.headers)
        self.assertEqual(result.content, b'video-fixture')
        self.assertEqual(result.headers['cache-control'], 'no-store')
        self.assertEqual((await self.client.get(f"/api/jobs/{job['id']}/assets/state.sqlite3", headers=self.headers)).status_code, 404)

    async def test_payload_limits_and_schema_validation(self):
        self.assertEqual((await self.client.post('/api/ideas/plan', content=b'a' * 128001, headers=self.headers)).status_code, 413)
        self.assertEqual((await self.client.post('/api/jobs', json={'plan': {}}, headers=self.headers)).status_code, 422)

@unittest.skipUnless(Renderer().available, 'FFmpeg/FFprobe not installed')
class RenderTests(unittest.IsolatedAsyncioTestCase):

    async def test_api_submission_to_real_mp4_download(self):
        with tempfile.TemporaryDirectory() as temporary:
            settings = Settings(data_dir=Path(temporary), client_id='oaiapp_test', api_key='fake')
            app = create_app(settings, content=FakeContent(), identity=FakeIdentity(),
                renderer=Renderer({'portrait': (180, 320), 'landscape': (320, 180), 'square': (180, 180)}))
            async with app.router.lifespan_context(app), httpx.AsyncClient(
                    transport=httpx.ASGITransport(app=app), base_url='http://testserver') as client:
                verifier = secrets.token_urlsafe(48)
                ticket = app.state.store.new_ticket({'id': 'a', 'name': 'Ada', 'email': None}, challenge(verifier))
                session = await client.post('/api/session/exchange', json={'code': ticket, 'verifier': verifier})
                headers = {'Authorization': 'Bearer ' + session.json()['token']}
                planned = await client.post('/api/ideas/plan', json={'messages': [{'role': 'user', 'content': 'Morning coffee'}]}, headers=headers)
                submitted = await client.post('/api/jobs', json={'plan': planned.json(), 'voice': 'coral', 'request_key': 'j' * 32}, headers=headers)
                self.assertEqual(submitted.status_code, 202)
                await asyncio.gather(*list(app.state.jobs.tasks.values()))
                job_id = submitted.json()['id']
                status = await client.get('/api/jobs/' + job_id, headers=headers)
                self.assertEqual(status.json()['status'], 'completed')
                downloaded = await client.get(f'/api/jobs/{job_id}/assets/video.mp4', headers=headers)
                self.assertEqual(downloaded.status_code, 200)
                self.assertEqual(downloaded.content[4:8], b'ftyp')
                self.assertEqual(len(downloaded.content), int(downloaded.headers['content-length']))
                self.assertEqual(len(status.json()['manifest']['scenes']), 2)

    async def test_real_mp4_pipeline_all_canvas_ratios(self):
        for ratio in ['portrait', 'landscape', 'square']:
            with self.subTest(ratio=ratio), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                store = Store(root)
                renderer = Renderer({'portrait': (180, 320), 'landscape': (320, 180), 'square': (180, 180)})
                jobs = Jobs(store, root, FakeContent(), renderer, 1)
                request = GenerationRequest(plan=sample_plan(ratio), request_key='r' * 32)
                job, _ = store.new_job('a', request.request_key, request.model_dump(), 10)
                jobs.start(job['id'], request)
                await asyncio.gather(*list(jobs.tasks.values()))
                result = store.job(job['id'], 'a')
                self.assertEqual(result['status'], 'completed', result['error'])
                directory = root / 'jobs' / job['id']
                self.assertTrue((directory / 'scene01.mp4').exists())
                self.assertFalse((directory / 'voice01.wav').exists())
                self.assertIn('00:00:02,000', (directory / 'captions.srt').read_text())
                metadata = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(directory / 'video.mp4')]))
                video = next((stream for stream in metadata['streams'] if stream['codec_type'] == 'video'))
                audio = next((stream for stream in metadata['streams'] if stream['codec_type'] == 'audio'))
                self.assertEqual(video['codec_name'], 'h264')
                self.assertEqual(audio['codec_name'], 'aac')
                self.assertEqual((video['width'], video['height']), renderer.dimensions[ratio])
                self.assertEqual(video['r_frame_rate'], '30/1')
                self.assertAlmostEqual(float(metadata['format']['duration']), 4, delta=0.15)
                self.assertIn('AI-generated', metadata['format']['tags']['comment'])
                await jobs.close()

    async def test_cancel_before_worker_starts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            store = Store(root)
            jobs = Jobs(store, root, SlowContent(), Renderer(), 1)
            request = GenerationRequest(plan=sample_plan(), request_key='c' * 32)
            job, _ = store.new_job('a', request.request_key, request.model_dump(), 10)
            jobs.start(job['id'], request)
            await jobs.cancel(job['id'])
            self.assertEqual(store.job(job['id'], 'a')['status'], 'cancelled')
            self.assertFalse((root / 'jobs' / job['id']).exists())

    async def test_shutdown_marks_unfinished_job_failed_and_cleans_partial_media(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); store = Store(root)
            jobs = Jobs(store, root, SlowContent(), Renderer(), 1)
            request = GenerationRequest(plan=sample_plan(), request_key='s' * 32)
            job, _ = store.new_job('a', request.request_key, request.model_dump(), 10)
            jobs.start(job['id'], request)
            await asyncio.sleep(0)
            self.assertTrue((root / 'jobs' / job['id']).exists())
            await jobs.close()
            self.assertEqual(store.job(job['id'], 'a')['status'], 'failed')
            self.assertFalse((root / 'jobs' / job['id']).exists())
if __name__ == '__main__':
    unittest.main()
