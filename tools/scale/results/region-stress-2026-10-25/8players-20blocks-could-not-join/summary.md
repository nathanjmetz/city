Run: 8 players with towns (0 people in the biggest), 2 late joiners, 709 s. Steady window [30, 301.7] s.

Server CPU (one core = 100): steady mean 7.6, p95 59.4, max 99.5. Seconds pinned over 90: 10. Memory 5562 MB at start, 4629 at end, 7269 peak.
Bytes: server takes in 0.0 KB/s steady (peak 6.3), sends out 0.0 KB/s steady (peak 13369.5). Whole run: 0.0 MB in, 13.7 MB out.
Server answer time (probe): {'n': 328, 'mean': 108.0, 'p50': 13.0, 'p95': 402.0, 'p99': 2003.0, 'max': 2765.0} ms; failed 0; over 1 s: 13; over 5 s: 0 of 328.
Sync lag on the wire (owner's copy in, neighbor's copy out): {'n': 0} s.
Neighbors' towns on screen at the end: behind by {'n': 0} buildings.

| player | people | p50 ms | p95 ms | worst ms | freezes >1 s | hitches >100 ms | dropped/back | KB/s up | KB/s down | CPU % | peak RSS MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bot1 | None | None | None | 1645.0 | 2 | 3 | 0/0 | 0.0 | 0.0 | 6 | 1328.5 |
| Bot2 | None | None | None | 1695.5 | 2 | 5 | 0/0 | 0.0 | 0.0 | 6 | 1328.9 |
| Bot3 | None | None | None | 1642.8 | 2 | 4 | 0/0 | 0.0 | 0.0 | 6 | 1325.4 |
| Bot4 | None | None | None | 1553.1 | 2 | 3 | 0/0 | 0.0 | 0.0 | 6 | 1327.3 |
| Bot5 | None | None | None | 1502.1 | 2 | 5 | 0/0 | 0.0 | 0.0 | 6 | 1324.6 |
| Bot6 | None | None | None | 1514.8 | 2 | 4 | 0/0 | 0.0 | 0.0 | 6 | 1324.0 |
| Bot7 | None | None | None | 1489.9 | 2 | 5 | 0/0 | 0.0 | 0.0 | 6 | 1325.3 |
| Bot8 | None | None | None | 1515.3 | 2 | 4 | 0/0 | 0.0 | 0.0 | 6 | 1321.6 |

| joiner | late | welcome MB | hello to welcome s | bot's load s |
|---|---|---|---|---|
| Late1 | yes | 13.69 | 4.44 |  |

Problems: Bot1: the town never finished loading; Bot2: the town never finished loading; Bot3: the town never finished loading; Bot4: the town never finished loading; Bot5: the town never finished loading; Bot6: the town never finished loading; Bot7: the town never finished loading; Bot8: the town never finished loading; ERROR: Condition "outbound_buffer_size > 0 && (wslay_event_get_queued_msg_length(wsl_ctx) + p_buffer_size > (uint32_t)outbound_buffer_size)" is true. Returning: ERR_OUT_OF_MEMORY
