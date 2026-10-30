#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p evidence3

docker run -i --rm --privileged -v "$PWD:/lab" -w /lab \
  firdaussahran/netlab-mininet:1.0 python3 build_routed.py network.yaml \
  > evidence3/session.txt 2>&1 <<'MININET'
net
h1 ping -c 1 h2
h1 ping -c 1 h3
h1 ping -c 1 h4
sh echo '== r1' > evidence3/routes.txt
r1 ip route >> evidence3/routes.txt
sh echo '== r2' >> evidence3/routes.txt
r2 ip route >> evidence3/routes.txt
sh echo '== r3' >> evidence3/routes.txt
r3 ip route >> evidence3/routes.txt
sh echo '== r4' >> evidence3/routes.txt
r4 ip route >> evidence3/routes.txt
h1 traceroute -n -I h2 > evidence3/traces.txt
h1 traceroute -n -I h3 >> evidence3/traces.txt
h1 traceroute -n -I h4 >> evidence3/traces.txt
r1 ip route get h3 > evidence3/summary.txt
r1 ip route get h4 >> evidence3/summary.txt
link r1 r4 down
h1 traceroute -n -I -m 5 -w 1 -q 1 h3 > evidence3/failure.txt
r1 ip route get h3 >> evidence3/failure.txt 2>&1
link r1 r4 up
exit
MININET

python3 - <<'PY'
from pathlib import Path
log = Path('evidence3/session.txt').read_text()
if log.count('0% packet loss') < 3:
    raise SystemExit('Not all three h1 ping checks succeeded; inspect evidence3/session.txt')
for name in ('routes', 'traces', 'summary', 'failure'):
    if not Path(f'evidence3/{name}.txt').read_text().strip():
        raise SystemExit(f'evidence3/{name}.txt is empty')
print('Week 3 evidence captured; inspect the routes, traces and link failure')
PY
