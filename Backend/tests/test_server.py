import copy
import hashlib
import http.client
import ipaddress
import json
import pathlib
import socket
import sys
import threading
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import server

SOURCE = 'https://vm.tiktok.com/authorized/'
TOKEN = 'test-only-' + 'x'*40
MANIFEST = {
    'id':'own-post', 'sourceURL':SOURCE, 'title':'Owned carousel', 'resolver':'authorized-catalog/1.0',
    'assets':[{'id':str(i), 'kind':'image', 'variants':[{'id':str(i)+'-original', 'url':'https://cdn.example.com/'+str(i)+'.jpg','mimeType':'image/jpeg','width':1920,'height':1080,'bytes':1200}]} for i in range(5)]
}

def no_network(raw):
    return server.normalize(raw)

def lookup_for(*addresses):
    def lookup(*args, **kwargs):
        return [(socket.AF_INET6 if ':' in address else socket.AF_INET,socket.SOCK_STREAM,6,'',(address,443)) for address in addresses]
    return lookup

class URLTests(unittest.TestCase):
    def test_normalize(self):
        self.assertEqual(server.normalize('https://EXAMPLE.com/a#b'),'https://example.com/a')
    def test_reject_invalid_urls(self):
        for url in ['http://example.com/a','file:///etc/passwd','https://user:pass@example.com/a','https://example.com:22/a','https://localhost/a','https://printer.local/a','https://example.com./a','https://example.com/\nheader']:
            with self.subTest(url=url), self.assertRaises(ValueError): server.normalize(url)
    def test_reject_private_dns(self):
        for address in ['127.0.0.1','10.0.0.1','169.254.169.254','172.16.0.1','192.168.1.1','100.64.0.1','0.0.0.0','224.0.0.1','::1','fc00::1','fe80::1','::ffff:127.0.0.1','2001:db8::1']:
            with self.subTest(address=address), self.assertRaises(ValueError):
                server.validate_public('https://example.com/a', lookup_for(address))
    def test_mixed_dns_rejected(self):
        with self.assertRaises(ValueError): server.validate_public('https://example.com/a',lookup_for('8.8.8.8','127.0.0.1'))
    def test_public_dns(self):
        self.assertEqual(server.validate_public('https://example.com/a',lookup_for('8.8.8.8')),'https://example.com/a')
    def test_no_dns_answers(self):
        with self.assertRaises(ValueError): server.validate_public('https://example.com/a',lookup_for())

class ContractTests(unittest.TestCase):
    def test_real_catalog_manifest(self):
        resolver=server.Resolver({hashlib.sha256(SOURCE.encode()).hexdigest():MANIFEST},no_network)
        self.assertEqual(len(resolver.resolve(SOURCE)['assets']),5)
    def test_missing_source_is_unavailable(self):
        with self.assertRaises(LookupError): server.Resolver({},no_network).resolve(SOURCE)
    def test_host_spoof_is_rejected(self):
        with self.assertRaises(ValueError): server.Resolver({},no_network).resolve('https://tiktok.com.evil.example/a')
    def test_source_mismatch(self):
        with self.assertRaises(ValueError): server.validate_manifest(MANIFEST,'https://www.tiktok.com/other/',no_network)
    def test_duplicate_assets(self):
        manifest=copy.deepcopy(MANIFEST); manifest['assets'][1]['id']='0'
        with self.assertRaises(ValueError): server.validate_manifest(manifest,SOURCE,no_network)
    def test_empty_variants(self):
        manifest=copy.deepcopy(MANIFEST); manifest['assets'][0]['variants']=[]
        with self.assertRaises(ValueError): server.validate_manifest(manifest,SOURCE,no_network)
    def test_invalid_mime(self):
        manifest=copy.deepcopy(MANIFEST); manifest['assets'][0]['variants'][0]['mimeType']='text/html'
        with self.assertRaises(ValueError): server.validate_manifest(manifest,SOURCE,no_network)
    def test_file_limit(self):
        manifest=copy.deepcopy(MANIFEST); manifest['assets'][0]['variants'][0]['bytes']=2**32
        with self.assertRaises(ValueError): server.validate_manifest(manifest,SOURCE,no_network)
    def test_private_output(self):
        manifest=copy.deepcopy(MANIFEST)
        with self.assertRaises(ValueError): server.validate_manifest(manifest,SOURCE,lambda raw: server.validate_public(raw,lookup_for('127.0.0.1')))
    def test_rate_limit(self):
        limit=server.RateLimit()
        self.assertTrue(all(limit.allow() for _ in range(30)))
        self.assertFalse(limit.allow())
    def test_weak_token_rejected(self):
        with self.assertRaises(ValueError): server.make_server(('127.0.0.1',0),'weak',{})

class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=server.make_server(('127.0.0.1',0),TOKEN,{hashlib.sha256(SOURCE.encode()).hexdigest():MANIFEST},no_network)
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True); cls.thread.start()
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
    def request(self,method,path,body=None,auth=True,headers=None):
        connection=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=5)
        try:
            h={'Content-Type':'application/json'}
            if auth: h['Authorization']='Bearer '+TOKEN
            h.update(headers or {})
            connection.request(method,path,body=body,headers=h)
            response=connection.getresponse()
            return response.status,json.loads(response.read())
        finally: connection.close()
    def test_auth_required(self): self.assertEqual(self.request('POST','/v1/resolve','{}',False)[0],401)
    def test_health(self): self.assertEqual(self.request('GET','/v1/health')[1]['adapter'],'authorized-catalog')
    def test_resolve(self):
        status,body=self.request('POST','/v1/resolve',json.dumps({'url':SOURCE}))
        self.assertEqual(status,200); self.assertEqual(len(body['assets']),5)
    def test_unavailable(self): self.assertEqual(self.request('POST','/v1/resolve',json.dumps({'url':'https://vm.tiktok.com/missing/'}))[0],422)
    def test_malformed_json(self): self.assertEqual(self.request('POST','/v1/resolve','{bad')[0],400)
    def test_extra_fields(self): self.assertEqual(self.request('POST','/v1/resolve',json.dumps({'url':SOURCE,'cookies':'forbidden'}))[0],400)
    def test_large_request(self): self.assertEqual(self.request('POST','/v1/resolve','x'*9000)[0],413)
    def test_content_type(self): self.assertEqual(self.request('POST','/v1/resolve','{}',headers={'Content-Type':'text/plain'})[0],415)
    def test_not_proxy(self): self.assertEqual(self.request('GET','/v1/fetch?url=https://example.com')[0],404)

if __name__ == '__main__': unittest.main()
