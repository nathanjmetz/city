Run: 4 players with towns (4408 people in the biggest), 2 late joiners, 823 s. Steady window [98.2, 711.6] s.

Server CPU (one core = 100): steady mean 7.4, p95 29.9, max 84.7. Seconds pinned over 90: 0. Memory 3175 MB at start, 1663 at end, 3449 peak.
Bytes: server takes in 249.1 KB/s steady (peak 7949.9), sends out 449.6 KB/s steady (peak 10503.0). Whole run: 202.5 MB in, 346.7 MB out.
Server answer time (probe): {'n': 404, 'mean': 13.0, 'p50': 13.0, 'p95': 16.0, 'p99': 28.0, 'max': 44.0} ms; failed 0; over 1 s: 0; over 5 s: 0 of 404.
Sync lag on the wire (owner's copy in, neighbor's copy out): {'n': 267, 'mean': 0.38, 'p50': 0.35, 'p95': 0.5, 'p99': 1.43, 'max': 3.87} s.
Neighbors' towns on screen at the end: behind by {'n': 20, 'mean': 264.0, 'p50': 348, 'p95': 723, 'p99': 723, 'max': 723} buildings.
Server loop steps over 100 ms: 3 (worst 206 ms) {'msg.hello': {'n': 2, 'max_ms': 206}, 'poll': {'n': 1, 'max_ms': 128}}.
City lines in frames over 100 ms (most in any one, per bot): {'Bot1': 2.8, 'Bot2': 2.2, 'Bot3': 2.6, 'Bot4': 3.0, 'Late1': 4.8, 'Late2': 6.9} ms.

| player | people | p50 ms | p95 ms | worst ms | freezes >1 s | hitches >100 ms | dropped/back | KB/s up | KB/s down | CPU % | peak RSS MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bot1 | 4351 | 302.5 | 757.0 | 12923.7 | 62 | 1794 | 0/0 | 69.3 | 89.1 | 96 | 4123.4 |
| Bot2 | 4398 | 312.7 | 771.1 | 13060.9 | 63 | 1799 | 0/0 | 66.3 | 91.6 | 96 | 4545.4 |
| Bot3 | 3280 | 348.6 | 837.2 | 13099.3 | 66 | 1687 | 0/0 | 56.1 | 96.3 | 97 | 5139.2 |
| Bot4 | 4408 | 290.0 | 780.0 | 13156.1 | 68 | 1803 | 0/0 | 53.8 | 97.1 | 94 | 5698.0 |
| Late1 | 1299 | 104.5 | 200.5 | 2454.9 | 12 | 637 | 0/0 | 1.8 | 32.2 | 93 | 1918.3 |
| Late2 | 1228 | 92.2 | 183.4 | 2504.7 | 9 | 570 | 0/0 | 1.8 | 43.2 | 95 | 2602.6 |

| joiner | late | welcome MB | hello to welcome s | bot's load s |
|---|---|---|---|---|
| Bot1 |  | 5.1 | 0.05 | 32.0 |
| Bot2 |  | 5.14 | 0.05 | 32.92 |
| Bot3 |  | 5.42 | 0.04 | 40.84 |
| Bot4 |  | 5.21 | 0.06 | 42.89 |
| Late1 | yes | 0.02 | 0.13 | 7.94 |
| Late2 | yes | 0.02 | 0.17 | 8.9 |

Problems: none
