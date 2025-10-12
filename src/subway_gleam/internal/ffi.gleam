import gleam/erlang/atom
import gleam/erlang/charlist
import gleam/list
import gleam/pair
import gleam/result

/// Extracts all files from a zip archive.
///
/// The result is given as a list of tuples #(Filename, Binary), where Binary is
/// a binary containing the extracted data of file Filename in the zip archive.
@external(erlang, "zip", "unzip")
fn unzip_ffi(
  bits: BitArray,
  options: List(atom.Atom),
) -> Result(List(#(charlist.Charlist, BitArray)), Nil)

// TODO: actually figure out error type
pub fn unzip(bits: BitArray) -> Result(List(#(String, BitArray)), Nil) {
  unzip_ffi(bits, [atom.create("memory")])
  // Convert from List(#(Charlist, BitArray))
  //           -> List(#(String, BitArray))
  |> result.map(list.map(_, pair.map_first(_, charlist.to_string)))
}
