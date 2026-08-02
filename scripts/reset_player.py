import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('100.65.103.71', username='akingofcrows', password='Midnight1', timeout=10)

passwd = 'StrongStr0ngPass!'
user = 'akingofcrows'

cmds = [
    f"mysql -u fablewood_user -p'{passwd}' pokemon_triad -e \"UPDATE triad_characters c JOIN triad_users u ON c.user_id=u.id SET c.location='Pallet Town' WHERE u.username='{user}';\"",
    f"mysql -u fablewood_user -p'{passwd}' pokemon_triad -e \"DELETE sp FROM triad_story_progress sp JOIN triad_users u ON sp.user_id=u.id WHERE u.username='{user}';\"",
    f"mysql -u fablewood_user -p'{passwd}' pokemon_triad -e \"SELECT u.username, c.location, c.trainer_name FROM triad_characters c JOIN triad_users u ON c.user_id=u.id WHERE u.username='{user}';\"",
    f"mysql -u fablewood_user -p'{passwd}' pokemon_triad -e \"SELECT COUNT(*) as story_rows FROM triad_story_progress sp JOIN triad_users u ON sp.user_id=u.id WHERE u.username='{user}';\"",
]

for cmd in cmds:
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=10)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    if out: print(out)
    if err: print('ERR:', err)

ssh.close()
print('Done!')
