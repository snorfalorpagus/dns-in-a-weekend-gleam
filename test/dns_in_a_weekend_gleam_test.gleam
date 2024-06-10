import dns_in_a_weekend_gleam.{A, DNSHeader, DNSPacket, DNSQuestion, DNSRecord}
import gleam/bit_array
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn header_to_bytes_test() {
  DNSHeader(0x1314, 0, 1, 0, 0, 0)
  |> dns_in_a_weekend_gleam.header_to_bytes
  |> bit_array.base16_encode
  |> should.equal("131400000001000000000000")
}

pub fn encode_dns_name_test() {
  "www.google.com"
  |> dns_in_a_weekend_gleam.encode_dns_name
  |> bit_array.base16_encode
  |> should.equal("0377777706676F6F676C6503636F6D00")
}

pub fn question_to_bytes_test() {
  DNSQuestion("w", A, 2)
  |> dns_in_a_weekend_gleam.question_to_bytes
  |> bit_array.base16_encode
  |> should.equal("01770000010002")
}

pub fn parse_name_test() {
  let assert Ok(name) =
    "0377777706676F6F676C6503636F6D00" |> bit_array.base16_decode
  dns_in_a_weekend_gleam.parse_name(name, bit_array.append(<<0:160>>, name))
  |> should.equal(Ok(#("www.google.com", <<>>)))
}

pub fn parse_packet_test() {
  let assert Ok(packet) =
    "856B8180000100010000000006676F6F676C6503636F6D0000010001C00C000100010000008700048EFABBCE"
    |> bit_array.base16_decode
  packet
  |> dns_in_a_weekend_gleam.parse_packet()
  |> should.equal(
    Ok(
      DNSPacket(
        DNSHeader(0x856b, 0x8180, 1, 1, 0, 0),
        [DNSQuestion("google.com", A, 1)],
        [DNSRecord("google.com", A, 1, 135, <<0x8e, 0xfa, 0xbb, 0xce>>)],
        [],
        [],
      ),
    ),
  )
}
