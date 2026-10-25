Run: 8 players with towns (1058 people in the biggest), 2 late joiners, 1766 s. Steady window [178.2, 1476.4] s.

Server CPU (one core = 100): steady mean 9.3, p95 55.4, max 98.0. Seconds pinned over 90: 14. Memory 3866 MB at start, 2664 at end, 6716 peak.
Bytes: server takes in 88.0 KB/s steady (peak 3781.5), sends out 479.7 KB/s steady (peak 16053.4). Whole run: 157.9 MB in, 869.2 MB out.
Server answer time (probe): {'n': 824, 'mean': 131.0, 'p50': 13.0, 'p95': 1062.0, 'p99': 1618.0, 'max': 5278.0} ms; failed 0; over 1 s: 46; over 5 s: 1 of 824.
Sync lag on the wire (owner's copy in, neighbor's copy out): {'n': 463, 'mean': 71.86, 'p50': 48.21, 'p95': 213.85, 'p99': 230.38, 'max': 247.1} s.
Neighbors' towns on screen at the end: behind by {'n': 72, 'mean': 258.0, 'p50': 279, 'p95': 341, 'p99': 373, 'max': 373} buildings.

| player | people | p50 ms | p95 ms | worst ms | freezes >1 s | hitches >100 ms | dropped/back | KB/s up | KB/s down | CPU % | peak RSS MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bot1 | 882 | 290.5 | 502.8 | 244358.5 | 31 | 750 | 0/0 | 10.4 | 52.8 | 98 | 4018.0 |
| Bot2 | 846 | 286.5 | 499.4 | 244873.5 | 28 | 750 | 0/0 | 9.5 | 53.4 | 97 | 4253.4 |
| Bot3 | 728 | 277.1 | 461.1 | 254021.3 | 35 | 759 | 0/0 | 10.6 | 51.8 | 97 | 3911.6 |
| Bot4 | 885 | 278.3 | 430.7 | 256528.0 | 30 | 750 | 0/0 | 10.8 | 51.0 | 97 | 3697.5 |
| Bot5 | 1058 | 292.9 | 534.5 | 254686.4 | 30 | 764 | 0/0 | 11.9 | 51.6 | 97 | 4151.8 |
| Bot6 | 784 | 340.3 | 608.7 | 254235.9 | 32 | 694 | 0/0 | 12.7 | 50.6 | 97 | 3457.0 |
| Bot7 | 913 | 295.4 | 465.4 | 254011.6 | 31 | 751 | 0/0 | 11.8 | 50.2 | 98 | 4283.2 |
| Bot8 | 875 | 295.7 | 476.2 | 255065.6 | 31 | 767 | 0/0 | 9.2 | 51.7 | 97 | 3784.9 |
| Late1 | 0 | 181.2 | 213.6 | 261798.0 | 12 | 284 | 0/0 | 0.4 | 33.5 | 96 | 2673.0 |
| Late2 | 0 | 196.3 | 1013.0 | 254619.0 | 13 | 291 | 0/0 | 0.6 | 33.2 | 96 | 2781.0 |

| joiner | late | welcome MB | hello to welcome s | bot's load s |
|---|---|---|---|---|
| Bot1 |  | 11.92 | 0.41 | 24.64 |
| Bot2 |  | 11.94 | 0.42 | 23.55 |
| Bot3 |  | 12.03 | 0.48 | 28.52 |
| Bot4 |  | 11.9 | 0.44 | 26.3 |
| Bot5 |  | 12.19 | 0.44 | 25.37 |
| Bot6 |  | 12.49 | 0.53 | 30.92 |
| Bot7 |  | 12.11 | 0.53 | 23.82 |
| Bot8 |  | 11.85 | 0.54 | 27.97 |
| Late1 | yes | 9.45 | 5.27 | 12.72 |
| Late2 | yes | 9.58 | 5.66 | 13.4 |

Problems: ERROR: Peer not found: 127339554
