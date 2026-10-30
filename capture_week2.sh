#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p evidence

docker run -i --rm --privileged -v "$PWD:/lab" -w /lab \
  firdaussahran/netlab-mininet:1.0 python3 build_topo.py topology.yaml \
  > evidence/session.txt 2>&1 <<'MININET'
net
pingall
h1 ping -6 -c 3 -W 2 fd00:3186::2
h1 ping -6 -c 1 -W 2 fd00:3186::2
h1 ip neigh > evidence/neigh.txt
sh brctl showmacs s1 > evidence/macs.txt
h2 ip -6 addr add fd00:3186::1/64 dev h2-eth0
h2 ip addr add 10.86.0.1/24 dev h2-eth0
sh sleep 4
h2 ip -6 addr show dev h2-eth0 > evidence/dad.txt
h2 ip -4 addr show dev h2-eth0 >> evidence/dad.txt
exit
MININET

python3 - <<'PY'
from pathlib import Path
import re
log = Path('evidence/session.txt').read_text()
match = re.search(r'\*\*\* Ping: testing ping reachability.*?\*\*\* Results:[^\n]*', log, re.S)
if match is None or '0% dropped' not in match.group():
    raise SystemExit('Week 2 pingall did not finish with 0% dropped; inspect evidence/session.txt')
Path('evidence/pingall.txt').write_text(match.group().strip() + '\n')
if '1 packets transmitted, 1 received' not in log:
    raise SystemExit('IPv6 h1-to-h2 ping did not succeed; inspect evidence/session.txt')
for name in ('neigh', 'macs', 'dad'):
    if not Path(f'evidence/{name}.txt').read_text().strip():
        raise SystemExit(f'evidence/{name}.txt is empty')
if 'dadfailed' not in Path('evidence/dad.txt').read_text():
    raise SystemExit('IPv6 DAD failure was not observed; inspect evidence/dad.txt')
print('Week 2 evidence captured and checked')
PY
