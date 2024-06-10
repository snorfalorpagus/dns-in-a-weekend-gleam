import argv
import gleam/bit_array
import gleam/bytes_builder
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string

import udp.{Active, Binary}

pub type DNSParserError {
  InvalidHeader
  InvalidName
  InvalidQuestion
  InvalidRecord
  SocketError
}

pub type DNSHeader {
  DNSHeader(
    id: Int,
    flags: Int,
    num_questions: Int,
    num_answers: Int,
    num_authorities: Int,
    num_additionals: Int,
  )
}

pub type RecordType {
  A
  NS
  CNAME
  MX
  TXT
  Unknown(Int)
}

pub type DNSQuestion {
  DNSQuestion(name: String, qtype: RecordType, qclass: Int)
}

pub type DNSRecord {
  DNSRecord(
    name: String,
    rtype: RecordType,
    rclass: Int,
    ttl: Int,
    data: BitArray,
  )
}

pub type DNSPacket {
  DNSPacket(
    header: DNSHeader,
    questions: List(DNSQuestion),
    answers: List(DNSRecord),
    authorities: List(DNSRecord),
    additionals: List(DNSRecord),
  )
}

pub fn header_to_bytes(header: DNSHeader) -> BitArray {
  <<
    header.id:int-big-size(16),
    header.flags:int-big-size(16),
    header.num_questions:int-big-size(16),
    header.num_answers:int-big-size(16),
    header.num_authorities:int-big-size(16),
    header.num_additionals:int-big-size(16),
  >>
}

fn record_type_to_int(record_type: RecordType) -> Int {
  case record_type {
    A -> 1
    NS -> 2
    CNAME -> 5
    MX -> 15
    TXT -> 16
    Unknown(value) -> value
  }
}

fn int_to_record_type(value: Int) -> RecordType {
  case value {
    1 -> A
    2 -> NS
    5 -> CNAME
    15 -> MX
    16 -> TXT
    value -> Unknown(value)
  }
}

pub fn question_to_bytes(question: DNSQuestion) -> BitArray {
  encode_dns_name(question.name)
  |> bit_array.append(<<
    record_type_to_int(question.qtype):int-big-size(16),
    question.qclass:int-big-size(16),
  >>)
}

pub fn record_to_bytes(record: DNSRecord) -> BitArray {
  let data_length = bit_array.byte_size(record.data) / 8
  encode_dns_name(record.name)
  |> bit_array.append(<<
    record_type_to_int(record.rtype):int-big-size(16),
    record.rclass:int-big-size(16),
    record.ttl:int-big-size(32),
    data_length:int-big-size(16),
  >>)
  |> bit_array.append(record.data)
}

pub fn build_query(
  domain_name: String,
  record_type: RecordType,
  recursion_wanted recursion: Bool,
) -> DNSPacket {
  let id = int.random(65_535)
  let header =
    DNSHeader(
      id: id,
      flags: case recursion {
        True -> int.bitwise_shift_left(1, 8)
        False -> 0
      },
      num_questions: 1,
      num_answers: 0,
      num_authorities: 0,
      num_additionals: 0,
    )
  let question = DNSQuestion(name: domain_name, qtype: record_type, qclass: 1)

  DNSPacket(header, [question], [], [], [])
}

pub fn packet_to_bytes(packet: DNSPacket) -> BitArray {
  bytes_builder.new()
  |> bytes_builder.append(header_to_bytes(packet.header))
  |> list.fold(
    packet.questions,
    _,
    fn(builder, question) {
      bytes_builder.append(builder, question_to_bytes(question))
    },
  )
  |> bytes_builder.to_bit_array()
}

pub fn encode_dns_name(name: String) -> BitArray {
  name
  |> string.split(".")
  |> list.map(fn(part) {
    let size = string.byte_size(part)
    <<size:int-big-size(8), part:utf8>>
  })
  |> bit_array.concat
  |> bit_array.append(<<0:int-big-size(8)>>)
}

pub fn parse_name(
  name: BitArray,
  body: BitArray,
) -> Result(#(String, BitArray), DNSParserError) {
  do_parse_name(name, body, [])
}

fn do_parse_name(
  name: BitArray,
  body: BitArray,
  accumulator: List(BitArray),
) -> Result(#(String, BitArray), DNSParserError) {
  case name {
    <<0:8, rest:bits>> -> {
      accumulator
      |> list.reverse
      |> list.map(bit_array.to_string)
      |> result.all
      |> result.map(fn(parts) { #(string.join(parts, "."), rest) })
      |> result.replace_error(InvalidName)
    }
    <<1:1, 1:1, pointer:int-big-size(14), rest:bits>> -> {
      // subtract the header length from the pointer, as we're working with the body only
      let pointer = { pointer - 12 } * 8
      case body {
        <<_:size(pointer), parts:bits>> -> {
          use #(name, _) <- result.try(do_parse_name(parts, body, []))
          Ok(#(name, rest))
        }
        _ -> Error(InvalidName)
      }
    }
    <<0:1, 0:1, length:int-big-size(6), rest:bits>> -> {
      let length = length * 8
      case rest {
        <<parts:bits-size(length), rest:bits>> ->
          do_parse_name(rest, body, [parts, ..accumulator])
        _ -> Error(InvalidName)
      }
    }
    _ -> Error(InvalidName)
  }
}

pub fn parse_header(
  message: BitArray,
) -> Result(#(DNSHeader, BitArray), DNSParserError) {
  case message {
    <<
      id:int-big-size(16),
      flags:int-big-size(16),
      num_questions:int-big-size(16),
      num_answers:int-big-size(16),
      num_authorities:int-big-size(16),
      num_additionals:int-big-size(16),
      rest:bits,
    >> -> {
      Ok(#(
        DNSHeader(
          id,
          flags,
          num_questions,
          num_answers,
          num_authorities,
          num_additionals,
        ),
        rest,
      ))
    }
    _ -> Error(InvalidHeader)
  }
}

pub fn parse_question(
  question: BitArray,
  body: BitArray,
) -> Result(#(DNSQuestion, BitArray), DNSParserError) {
  case parse_name(question, body) {
    Ok(#(name, <<qtype:int-big-size(16), qclass:int-big-size(16), rest:bits>>)) -> {
      Ok(#(DNSQuestion(name, int_to_record_type(qtype), qclass), rest))
    }
    _ -> Error(InvalidQuestion)
  }
}

fn parse_questions(
  questions: BitArray,
  body: BitArray,
  count: Int,
) -> Result(#(List(DNSQuestion), BitArray), DNSParserError) {
  do_parse_questions(questions, body, count, [])
}

fn do_parse_questions(
  questions: BitArray,
  body: BitArray,
  count: Int,
  accumulator: List(DNSQuestion),
) -> Result(#(List(DNSQuestion), BitArray), DNSParserError) {
  case count {
    0 -> Ok(#(list.reverse(accumulator), questions))
    count if count > 0 -> {
      case parse_question(questions, body) {
        Ok(#(record, rest)) -> {
          do_parse_questions(rest, body, count - 1, [record, ..accumulator])
        }
        Error(_) -> Error(InvalidRecord)
      }
    }
    _ -> panic
  }
}

pub fn parse_record(
  record: BitArray,
  body: BitArray,
) -> Result(#(DNSRecord, BitArray), DNSParserError) {
  case parse_name(record, body) {
    Ok(#(name, rest)) -> {
      case rest {
        <<
          qtype:int-big-size(16),
          qclass:int-big-size(16),
          ttl:int-big-size(32),
          data_length:int-big-size(16),
          rest:bits,
        >> -> {
          let data_length = data_length * 8
          case rest {
            <<data:bits-size(data_length), rest:bits>> ->
              Ok(#(
                DNSRecord(name, int_to_record_type(qtype), qclass, ttl, data),
                rest,
              ))
            _ -> Error(InvalidRecord)
          }
        }
        _ -> Error(InvalidRecord)
      }
    }
    Error(err) -> Error(err)
  }
}

fn parse_records(
  records: BitArray,
  body: BitArray,
  count: Int,
) -> Result(#(List(DNSRecord), BitArray), DNSParserError) {
  do_parse_records(records, body, count, [])
}

fn do_parse_records(
  records: BitArray,
  body: BitArray,
  count: Int,
  accumulator: List(DNSRecord),
) -> Result(#(List(DNSRecord), BitArray), DNSParserError) {
  case count {
    0 -> Ok(#(list.reverse(accumulator), records))
    count if count > 0 -> {
      case parse_record(records, body) {
        Ok(#(record, rest)) -> {
          do_parse_records(rest, body, count - 1, [record, ..accumulator])
        }
        Error(err) -> Error(err)
      }
    }
    _ -> panic
  }
}

pub fn parse_packet(packet: BitArray) -> Result(DNSPacket, DNSParserError) {
  // io.debug(packet)
  use #(header, body) <- result.try(parse_header(packet))
  use #(questions, rest) <- result.try(parse_questions(
    body,
    body,
    header.num_questions,
  ))
  use #(answers, rest) <- result.try(parse_records(
    rest,
    body,
    header.num_answers,
  ))
  use #(authorities, rest) <- result.try(parse_records(
    rest,
    body,
    header.num_authorities,
  ))
  use #(additionals, _rest) <- result.try(parse_records(
    rest,
    body,
    header.num_additionals,
  ))
  Ok(DNSPacket(header, questions, answers, authorities, additionals))
}

pub fn parse_ip4_address(data: BitArray) -> Result(#(Int, Int, Int, Int), Nil) {
  case data {
    <<
      a:int-big-size(8),
      b:int-big-size(8),
      c:int-big-size(8),
      d:int-big-size(8),
    >> -> {
      Ok(#(a, b, c, d))
    }
    _ -> Error(Nil)
  }
}

pub fn format_ip4_address(address: #(Int, Int, Int, Int)) -> String {
  let #(a, b, c, d) = address
  string.join(list.map([a, b, c, d], int.to_string), ".")
}

pub fn send_query(
  nameserver: #(Int, Int, Int, Int),
  domain: String,
) -> Result(DNSPacket, DNSParserError) {
  io.println(
    string.concat(["Querying ", format_ip4_address(nameserver), " for ", domain]),
  )
  let query =
    build_query(domain, A, recursion_wanted: False) |> packet_to_bytes()

  case do_send_query(nameserver, query) {
    Ok(data) -> parse_packet(data)
    Error(err) -> Error(err)
  }
}

pub fn do_send_query(
  nameserver: #(Int, Int, Int, Int),
  query: BitArray,
) -> Result(BitArray, DNSParserError) {
  {
    use socket <- result.try(udp.open(0, [Binary, Active(udp.False)]))

    use _ <- result.try(udp.send(
      socket,
      nameserver,
      53,
      bytes_builder.from_bit_array(query),
    ))

    use #(_address, _port, data) <- result.try(
      udp.recv(socket, 1024) |> result.replace_error(Nil),
    )

    Ok(data)
  }
  |> result.replace_error(SocketError)
}

pub fn resolve(
  nameserver: #(Int, Int, Int, Int),
  domain: String,
) -> Result(List(#(Int, Int, Int, Int)), Nil) {
  case send_query(nameserver, domain) {
    Ok(packet) -> {
      let answers =
        packet.answers |> list.filter(fn(record) { record.rtype == A })
      let additionals =
        packet.additionals |> list.filter(fn(record) { record.rtype == A })
      let authorities =
        packet.authorities |> list.filter(fn(record) { record.rtype == NS })
      case packet {
        _ if answers != [] -> {
          answers
          |> list.map(fn(record) { parse_ip4_address(record.data) })
          |> result.all()
          |> result.replace_error(Nil)
        }
        _ if additionals != [] -> {
          let assert [additional, ..] = additionals
          let assert Ok(nameserver) = parse_ip4_address(additional.data)
          resolve(nameserver, domain)
        }
        _ if authorities != [] -> {
          let assert [authority, ..] = authorities
          let assert Ok(#(ns, _)) = authority.data |> parse_name(<<>>)
          let assert Ok(nameservers) = resolve(#(198, 41, 0, 4), ns)
          let assert [nameserver, ..] = nameservers
          resolve(nameserver, domain)
        }
        _ -> Error(Nil)
      }
    }
    Error(_) -> Error(Nil)
  }
}

const a_root_server = #(198, 41, 0, 4)

pub fn main() {
  case argv.load().arguments {
    [domain] -> {
      case resolve(a_root_server, domain) {
        Ok(addresses) -> {
          addresses
          |> list.map(fn(address) {
            io.println(string.concat(["Answer: ", format_ip4_address(address)]))
          })
          Nil
        }
        Error(_) -> {
          io.println("No addresses found")
        }
      }
      Ok(Nil)
    }
    _ -> {
      io.println("Usage: dns_in_a_weekend <domain>")
      Error(Nil)
    }
  }
}
