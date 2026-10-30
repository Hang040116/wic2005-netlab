# WIC2005 Programmable Networks lab portfolio

This repository holds the Week 2 and Week 3 assignments for student ID suffix 3186. The full student ID is not stored here.

## Week 2: network from data

`topology.yaml` describes three Linux bridges, six hosts, and their links. `build_topo.py` validates IPv4 and IPv6 addresses, duplicate addresses, and link endpoints before starting Mininet. `make_page.py` reads the same topology and produces `docs/index.html`. `topology.json` is the same model in a second serialisation.

Run inside the [course Mininet container](https://firdaussahran.github.io/wic2005/weeks/week-02/#lab):

```sh
docker run -it --rm --privileged -v "${PWD}:/lab" -w /lab firdaussahran/netlab-mininet:1.0
python3 build_topo.py topology.yaml
python3 make_page.py topology.yaml
```

`bad.yaml` deliberately duplicates both IP versions and names a missing switch. Its error output is in `evidence/check.txt`. Other evidence files record reachability, neighbour discovery, bridge learning, and IPv6 Duplicate Address Detection.

## Week 3: routed network from data

`network.yaml` describes four routers in a ring, with one host on each LAN. The two LANs in `10.86.32.0/23` are reached through summary routes. `build_routed.py` checks all host-to-host paths for missing routes and loops before it builds. `make_page3.py` produces `docs/week3/index.html` from the same data.

```sh
python3 build_routed.py network.yaml
python3 make_page3.py network.yaml
```

`loop.yaml` and `missing.yaml` are negative cases. The outputs in `evidence3/check.txt` show that both fail before the network is built. The other files in `evidence3/` record live routing tables, traces, summary lookups, and a link failure.

