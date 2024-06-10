import gleam/bytes_builder.{type BytesBuilder}

pub type Socket

pub type ActiveType {
  True
  False
  Once
}

pub type SocketOption {
  Binary
  Active(ActiveType)
  Sndbuf(Int)
  Recbuf(Int)
}

pub type IpAddress =
  #(Int, Int, Int, Int)

@external(erlang, "gen_udp", "open")
pub fn open(port: Int, opts: List(SocketOption)) -> Result(Socket, Nil)

@external(erlang, "udp_ffi", "send")
pub fn send(
  socket: Socket,
  host: IpAddress,
  port: Int,
  packet: BytesBuilder,
) -> Result(String, Nil)

pub type RecvData =
  #(IpAddress, Int, BitArray)

@external(erlang, "gen_udp", "recv")
pub fn recv(socket: Socket, length: Int) -> Result(RecvData, String)
