def nonmt([maxseq, nm_count], [tcpseq]):
  if maxseq > tcpseq then
    nm_count = nm_count + 1
  if maxseq < tcpseq then
    maxseq = tcpseq

tcp_pkts = SELECT * FROM T WHERE proto == TCP;
nmo_query = SELECT [srcip, dstip, srcport, dstport, proto, nonmt] GROUPBY [srcip, dstip, srcport, dstport, proto] FROM tcp_pkts;