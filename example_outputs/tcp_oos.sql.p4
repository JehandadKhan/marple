/**
 * Do NOT modify manually.
 * This code is autogenerated.
 * Any changes you wish to make should be made to p4.tmpl and groupby.tmpl
 */

#include <core.p4>
#include <v1model.p4>

// This program processes packets composed of an Ethernet and
// an IPv4 header, performing forwarding based on the
// destination IP address

typedef bit<48>  EthernetAddress;
typedef bit<32>  IPv4Address;

// standard Ethernet header
header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

// IPv4 header without options
header ipv4_t {
    bit<4>       version;
    bit<4>       ihl;
    bit<8>       diffserv;
    bit<16>      packet_length;
    bit<16>      identification;
    bit<3>       flags;
    bit<13>      fragOffset;
    bit<8>       ttl;
    bit<8>       protocol;
    bit<16>      hdrChecksum;
    IPv4Address  srcAddr;
    IPv4Address  dstAddr;
}

header tcp_t {
    bit<16> srcport;
    bit<16> dstport;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<8>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length_;
    bit<16> checksum;
}

// Parser section

// List of all recognized headers
struct Headers {
    ethernet_t ethernet;
    ipv4_t     ip;
    tcp_t tcp;
    udp_t udp;
}

struct queueing_metadata_t {
    bit<48> enq_timestamp;
    bit<16> enq_qdepth;
    bit<32> deq_timedelta;
    bit<16> deq_qdepth;
}

struct intrinsic_metadata_t {
    bit<48> ingress_global_timestamp;
    bit<8> lf_field_list;
    bit<16> mcast_grp;
    bit<16> egress_rid;
    bit<8> resubmit_flag;
    bit<8> recirculate_flag;
}

struct CommonMetadata {
    bit<32> switchId;
    bit<32> payload_length;
    bit<32> egress_timestamp;
    bit<32> pktpath;
    bit<32> srcport;
    bit<32> dstport;
}

// Template hole: all temporary fields used in the query
struct QueryMetadata {
  bit<1> _tcp_pkts_valid;

  bit<1> _oos_query_valid;

  bit<32> lastseq;

  bit<32> oos_count;


}

// Template hole: key and value structs, one for each groupby
struct Key_oos_query {
  bit<32> f0;
  bit<32> f1;
  bit<32> f2;
  bit<32> f3;
  bit<32> f4;
  bit<32> f5;

}

struct Value_oos_query {
  bit<32> f0;
  bit<32> f1;

}



struct Metadata {
    QueryMetadata query_meta;
    // The structs below are read only.
    CommonMetadata common_meta;
    @name("intrinsic_metadata")
    intrinsic_metadata_t intrinsic_metadata;
    @name("queueing_metadata")
    queueing_metadata_t queueing_metadata; 
}

parser P(packet_in b,
         out Headers p,
         inout Metadata meta,
         inout standard_metadata_t standard_meta) {
    state start {
        b.extract(p.ethernet);
        transition select(p.ethernet.etherType) {
            0x0800 : parse_ipv4;
            // no default rule: all other packets rejected
        }
    }

    state parse_ipv4 {
        b.extract(p.ip);
        transition select(p.ip.fragOffset, p.ip.ihl, p.ip.protocol) {
            (13w0x0 &&& 13w0x0, 4w0x5 &&& 4w0xf, 8w0x6 &&& 8w0xff): parse_tcp;
            (13w0x0 &&& 13w0x0, 4w0x5 &&& 4w0xf, 8w0x11 &&& 8w0xff): parse_udp;
            default: accept;
        }
    }

    state parse_tcp {
        b.extract(p.tcp);
        transition accept;
    }

    state parse_udp {
        b.extract(p.udp);
        transition accept;
    }
}

// match-action pipeline section

control Ing(inout Headers headers,
            inout Metadata meta,
            inout standard_metadata_t standard_meta) {

    /**
     * Indicates that a packet is dropped by setting the
     * output port to the DROP_PORT
     */
    action Drop_action() {
        standard_meta.drop = 1w1;
    }

    /**
     * Set the next hop and the output port.
     * @param ivp4_dest ipv4 address of next hop
     * @param port output port
     */
    action Set_nhop(out IPv4Address nextHop,
                    IPv4Address ipv4_dest,
                    bit<9> outPort) {
        nextHop = ipv4_dest;
        standard_meta.egress_spec = outPort;
    }

    /**
     * Computes address of next Ipv4 hop and output port
     * based on the Ipv4 destination of the current packet.
     * Decrements packet Ipv4 TTL.
     * @param nextHop Ipv4 address of next hop
     */
    table ipv4_match(out IPv4Address nextHop) {
        key = { headers.ip.dstAddr : lpm; }
        actions = {
            Drop_action;
            Set_nhop(nextHop);
        }

        size = 1024;
        default_action = Drop_action;
    }

    //table check_ttl() {
    //    key = { headers.ip.ttl : exact; }
    //    actions = { Drop_action; NoAction; }
    //    const default_action = NoAction;
    //}

    /**
     * Set the destination MAC address of the packet
     * @param dmac destination MAC address.
     */
    action Set_dmac(EthernetAddress dmac) {
        headers.ethernet.dstAddr = dmac;
    }

    /**
     * Set the destination Ethernet address of the packet
     * based on the next hop IP address.
     * @param nextHop Ipv4 address of next hop.
     */
    table dmac(in IPv4Address nextHop) {
       key = { nextHop : exact; }
       actions = {
            Drop_action;
            Set_dmac;
       }
       size = 1024;
       default_action = Drop_action;
   }

   /**
    * Set the source MAC address.
    * @param smac: source MAC address to use
    */
    action Set_smac(EthernetAddress smac)
       { headers.ethernet.srcAddr = smac; }

      /**
       * Set the source mac address based on the output port.
       */
      table smac() {
           key = { standard_meta.egress_port : exact; }
           actions = {
                Drop_action;
                Set_smac;
          }
          size = 16;
          default_action = Drop_action;
      }

    apply {
        IPv4Address nextHop;
        ipv4_match.apply(nextHop); // Match result will go into nextHop
        dmac.apply(nextHop);
        smac.apply();
    }
}

control Eg(inout Headers hdrs,
           inout Metadata meta,
           inout standard_metadata_t standard_meta) {
    // Template hole: All the default actions, one for each stage
    action tcp_pkts() {
    // Preamble
    bool _tmp_tcp_pkts_valid;
    // Function body
    _tmp_tcp_pkts_valid = ((bit<32>)hdrs.ip.protocol) == (32w6);
    // Postamble
    meta.query_meta._tcp_pkts_valid = _tmp_tcp_pkts_valid ? (1w1) : (1w0);

    } 
    // Some overall comments pertaining to groupbys:
    // 1. inKey represents the incoming key. evictedKey and evictedValue represent evicted keys and values (if any).
    // 2. inKey and evictedKey are of type struct Key_oos_query. evictedValue is of type struct Value_oos_query.
    // 3. The fields within both structs are named f0, f1, f2, ...
    // 4. The reason we use these opaque names (f0) is because the key fields have fully qualified names, e.g., foo.bar.
    // 5. And the name key.foo.bar.... doesn't work without resorting to nested structs.

    // Template hole: register for each field in key
    register<bit<32>>(32w1024) regK_oos_query_f0;
    register<bit<32>>(32w1024) regK_oos_query_f1;
    register<bit<32>>(32w1024) regK_oos_query_f2;
    register<bit<32>>(32w1024) regK_oos_query_f3;
    register<bit<32>>(32w1024) regK_oos_query_f4;
    register<bit<32>>(32w1024) regK_oos_query_f5;


    // Template hole: register for each field in value
    register<bit<32>>(32w1024) regV_oos_query_f0;
    register<bit<32>>(32w1024) regV_oos_query_f1;


    // Template hole: action signature for groupby
    action oos_query(inout Key_oos_query evictedKey, inout Value_oos_query evictedValue) {

        // Template hole: Populate inKey's fields from the current packet.
        Key_oos_query inKey;
        inKey.f0 = hdrs.ip.srcAddr;
        inKey.f1 = meta.common_meta.switchId;
        inKey.f2 = hdrs.ip.dstAddr;
        inKey.f3 = meta.common_meta.srcport;
        inKey.f4 = meta.common_meta.dstport;
        inKey.f5 = (bit<32>)hdrs.ip.protocol;


        // Template hole: existingKey_* and existingValue_* are the
        // key and value fields that already exist in the computed hash bucket.
        bit<32> existingKey_f0 = 0;
        bit<32> existingKey_f1 = 0;
        bit<32> existingKey_f2 = 0;
        bit<32> existingKey_f3 = 0;
        bit<32> existingKey_f4 = 0;
        bit<32> existingKey_f5 = 0;

        bit<32> existingValue_f0 = 0;
        bit<32> existingValue_f1 = 0;


        // Template hole: hash inKey into hash table to compute hash index
        bit<32> hash_table_index = 32w0;
        hash(hash_table_index, HashAlgorithm.crc32, 32w0, inKey, 32w1024);

        // Template hole: Use hash_table_index to read out existing key and value
        regK_oos_query_f0.read(existingKey_f0, hash_table_index);
        regK_oos_query_f1.read(existingKey_f1, hash_table_index);
        regK_oos_query_f2.read(existingKey_f2, hash_table_index);
        regK_oos_query_f3.read(existingKey_f3, hash_table_index);
        regK_oos_query_f4.read(existingKey_f4, hash_table_index);
        regK_oos_query_f5.read(existingKey_f5, hash_table_index);

        regV_oos_query_f0.read(existingValue_f0, hash_table_index);
        regV_oos_query_f1.read(existingValue_f1, hash_table_index);


        // Template hole: Check if no key is present at hash_table_index
        bool no_key_present = true;
        no_key_present = (existingKey_f0 == 0) ? no_key_present : false;
        no_key_present = (existingKey_f1 == 0) ? no_key_present : false;
        no_key_present = (existingKey_f2 == 0) ? no_key_present : false;
        no_key_present = (existingKey_f3 == 0) ? no_key_present : false;
        no_key_present = (existingKey_f4 == 0) ? no_key_present : false;
        no_key_present = (existingKey_f5 == 0) ? no_key_present : false;


        // Template hole: Check if there is a match in the hash table (inKey matches against a stored key)
        bool key_matches = true;
        key_matches = (existingKey_f0 == inKey.f0) ? key_matches : false;
        key_matches = (existingKey_f1 == inKey.f1) ? key_matches : false;
        key_matches = (existingKey_f2 == inKey.f2) ? key_matches : false;
        key_matches = (existingKey_f3 == inKey.f3) ? key_matches : false;
        key_matches = (existingKey_f4 == inKey.f4) ? key_matches : false;
        key_matches = (existingKey_f5 == inKey.f5) ? key_matches : false;


        // Template hole: There is no eviction if either existingKey == inKey or existingKey == 0.
        bool ok = key_matches || no_key_present;
        evictedKey.f0   = !ok ? existingKey_f0     : 0;
        evictedKey.f1   = !ok ? existingKey_f1     : 0;
        evictedKey.f2   = !ok ? existingKey_f2     : 0;
        evictedKey.f3   = !ok ? existingKey_f3     : 0;
        evictedKey.f4   = !ok ? existingKey_f4     : 0;
        evictedKey.f5   = !ok ? existingKey_f5     : 0;

        evictedValue.f0 = !ok ? existingValue_f0   : 0;
        evictedValue.f1 = !ok ? existingValue_f1   : 0;


        // Template hole: Get value if there is no eviction, pass this on to update code
        bit<32> _val_lastseq = ok ? existingValue_f0  : 0;
        bit<32> _val_oos_count = ok ? existingValue_f1  : 0;


        // Template hole: Execute code that updates value registers.
        // The code should reference values by their _val_* variable names directly.
        // Preamble
        bool _tmp_oos_query_valid;
        bool _tmp_tcp_pkts_valid;
        _tmp_tcp_pkts_valid = (meta.query_meta._tcp_pkts_valid) == (1w1);
        // Function body
        bool _pred_1;
        bit<32> tmp;
        bool _pred_2;
        bool _pred_3;
        bit<32> _oos_count_a;
        bit<32> _oos_count_b;
        _tmp_oos_query_valid = false;
        _oos_count_a = 32w1;
        _oos_count_b = 32w0;
        _pred_1 = _tmp_tcp_pkts_valid;
        _pred_2 = (_val_lastseq) != (hdrs.tcp.seqNo);
        _pred_3 = (_pred_1) && (_pred_2);
        _oos_count_a = _pred_3 ? ((_oos_count_a)*(32w1)) : (_oos_count_a);
        _oos_count_b = _pred_3 ? ((32w1)+((32w1)*(_oos_count_b))) : (_oos_count_b);
        tmp = (hdrs.tcp.seqNo)+(meta.common_meta.payload_length);
        _val_lastseq = tmp;
        _val_oos_count = ((_oos_count_a)*(_val_oos_count))+(_oos_count_b);
        // Postamble
        meta.query_meta._oos_query_valid = _tmp_oos_query_valid ? (1w1) : (1w0);


        // Template hole: Write the inKey and the updated (or initial) value into the register.
        regK_oos_query_f0.write(hash_table_index, inKey.f0);
        regK_oos_query_f1.write(hash_table_index, inKey.f1);
        regK_oos_query_f2.write(hash_table_index, inKey.f2);
        regK_oos_query_f3.write(hash_table_index, inKey.f3);
        regK_oos_query_f4.write(hash_table_index, inKey.f4);
        regK_oos_query_f5.write(hash_table_index, inKey.f5);

        regV_oos_query_f0.write(hash_table_index, _val_lastseq);
        regV_oos_query_f1.write(hash_table_index, _val_oos_count);

    }
     


    apply {
        // Template hole: switch identifier
        meta.common_meta.switchId = 666;
        meta.common_meta.payload_length = hdrs.tcp.isValid() ? (bit<32>)hdrs.ip.packet_length - (bit<32>)hdrs.tcp.dataOffset : (bit<32>)hdrs.udp.length_;
        meta.common_meta.egress_timestamp = meta.queueing_metadata.enq_timestamp[31:0] + (bit<32>)meta.queueing_metadata.deq_timedelta;
        meta.common_meta.pktpath = 0;
        meta.common_meta.srcport = (hdrs.tcp.srcport != 0) ? (bit<32>)hdrs.tcp.srcport : (bit<32>)hdrs.udp.srcPort;
        meta.common_meta.dstport = (hdrs.tcp.srcport != 0) ? (bit<32>)hdrs.tcp.dstport : (bit<32>)hdrs.udp.dstPort;

        // Template hole: Call all the default actions within the control flow
        tcp_pkts();
         
        Key_oos_query  evictedKey_oos_query;
        Value_oos_query evictedValue_oos_query;
        oos_query(evictedKey_oos_query,evictedValue_oos_query);
         

    }
}

// deparser section
control DP(packet_out b, in Headers p) {
    apply {
        b.emit(p.ethernet);
        b.emit(p.ip);
        b.emit(p.tcp);
        b.emit(p.udp);
    }
}

// Fillers
control Verify(in Headers hdrs, inout Metadata meta) {
    apply {}
}

control Compute(inout Headers hdr, inout Metadata meta) {
    apply {}
}

// Instantiate the top-level V1 Model package.
V1Switch(P(),
         Verify(),
         Ing(),
         Eg(),
         Compute(),
         DP()) main;