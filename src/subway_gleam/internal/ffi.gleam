import gleam/erlang/atom

/// Extracts all files from a zip archive.
///
/// The result is given as a list of tuples #(Filename, Binary), where Binary is
/// a binary containing the extracted data of file Filename in the zip archive.
@external(erlang, "zip", "unzip")
fn unzip_ffi(
  bits: BitArray,
  options: List(atom.Atom),
) -> Result(List(#(String, BitArray)), String)

pub fn unzip(bits: BitArray) -> Result(List(#(String, BitArray)), String) {
  unzip_ffi(bits, [atom.create("memory")])
}
