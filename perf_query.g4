grammar perf_query;

// Skip whitespace
WS : [ \n\t\r]+ -> skip;

// Keywords
SELECT : 'SELECT' | 'select' ;
WHERE : 'WHERE' | 'where' ;
FROM : 'FROM' | 'from' ;
GROUPBY : 'GROUPBY' | 'groupby';
JOIN   : 'JOIN' | 'join';
IF     : 'IF' | 'if';
THEN   : 'THEN' | 'then';
ELSE   : 'ELSE' | 'else';
DEF    : 'def';
PKTLOG : 'T' ;

// Fields
field : 'srcip'
      | 'dstip'
      | 'srcport'
      | 'dstport'
      | 'proto'
      | 'pkt_path'
      | 'pkt_len'
      | 'payload_len'
      | 'tcpseq'
      | 'qid'
      | 'tin'
      | 'tout'
      | 'qin'
      | 'qout'
      | 'uid';

// Field list
field_with_comma : ',' field;
field_list : '[' field ']'
           | '[' field field_with_comma+ ']';

// Identifiers
ID : ('a'..'z' | 'A'..'Z' | '_') ('a'..'z' | 'A'..'Z' | '_' | '0'..'9')*;
VALUE : [0-9]+ ;

// Id list
id_with_comma : ',' ID;
id_list : '[' ID ']'
        | '[' ID id_with_comma+ ']';

// Field or Id list
fid_with_comma : ',' (ID | field);
fid_list : '[' (ID | field) ']'
         | '[' (ID | field) fid_with_comma+ ']';

// Expressions
expr : ID
     | VALUE
     | field
     | expr '+' expr
     | expr '-' expr
     | expr '*' expr
     | expr '/' expr
     | '(' expr ')';

// Predicates or filters
predicate : expr '==' expr
          | expr '>' expr
          | expr '<' expr
          | expr '!=' expr
          | predicate '&&' predicate
          | predicate '||' predicate
          | '(' predicate ')'
          | '!' predicate ;

// Aggregation functions for group by
stmt : ID '=' expr
     | ';'
     | IF predicate THEN stmt (ELSE stmt)?;

agg_fun : DEF ID '(' id_list ',' field_list ')' ':' stmt+;

// Main production rule for queries
prog : (agg_fun)* (ID '=' query ';')+;
query : SELECT (field_list | '*') FROM (ID | PKTLOG) (WHERE predicate)?
      | SELECT fid_list GROUPBY field_list FROM (ID | PKTLOG) (WHERE predicate)?
      | (ID | PKTLOG) JOIN (ID | PKTLOG);