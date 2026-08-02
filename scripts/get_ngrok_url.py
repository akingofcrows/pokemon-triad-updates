import paramiko, json, urllib.request

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('100.65.103.71', username='akingofcrows', password='Midnight1', timeout=10)

stdin, stdout, stderr = ssh.exec_command('curl -s http://localhost:4040/api/tunnels', timeout=10)
data = json.loads(stdout.read().decode())
url = data['tunnels'][0]['public_url']
print(url)
ssh.close()
