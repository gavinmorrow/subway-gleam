import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gtfs_rt_nyct
import lustre/element

/// Text that contains styling and icons (e.g. route bullets).
pub opaque type RichText {
  // TODO: is there a better representation of this?
  /// Currently stores an HTML string.
  RichText(String)
}

pub fn as_html(rich_text: RichText) -> element.Element(msg) {
  let RichText(raw_html) = rich_text
  element.unsafe_raw_html("", "div", [], raw_html)
}

pub fn from_translated_string(text: gtfs_rt_nyct.TranslatedString) -> RichText {
  let gtfs_rt_nyct.TranslatedString(translations:) = text
  let translations =
    list.fold(over: translations, from: dict.new(), with: fn(acc, translation) {
      dict.insert(translation.text, for: translation.language, into: acc)
    })

  // Okay to assert because there must be at least one translation
  let assert Ok(text) =
    dict.get(translations, option.Some("en-html"))
    // Fallbacks
    |> result.or(dict.get(translations, option.Some("en")))
    |> result.or(dict.get(translations, option.None))
    // there must be at least one translation
    |> result.or(dict.values(translations) |> list.first)

  replace_bracketed_symbols(text)
}

fn replace_bracketed_symbols(text: String) -> RichText {
  do_replace_bracketed_symbols(string.to_graphemes(text), "")
}

fn do_replace_bracketed_symbols(
  remaining_graphemes: List(String),
  acc_html: String,
) -> RichText {
  case remaining_graphemes {
    [] -> RichText(acc_html)
    ["[", ..remaining_graphemes] -> {
      let #(remaining_graphemes, symbol_html) =
        consume_bracketed_symbol(remaining_graphemes, "")
      do_replace_bracketed_symbols(remaining_graphemes, acc_html <> symbol_html)
    }
    [grapheme, ..remaining_graphemes] ->
      do_replace_bracketed_symbols(remaining_graphemes, acc_html <> grapheme)
  }
}

fn consume_bracketed_symbol(
  remaining_graphemes: List(String),
  acc_symbol_name: String,
) -> #(List(String), String) {
  case remaining_graphemes {
    // The empty case really shouldn't ever happen, but if it does just consider
    // it the end of the symbol name
    [] as remaining_graphemes | ["]", ..remaining_graphemes] -> #(
      remaining_graphemes,
      bracketed_symbol_to_html(acc_symbol_name),
    )
    [grapheme, ..remaining_graphemes] ->
      consume_bracketed_symbol(remaining_graphemes, acc_symbol_name <> grapheme)
  }
}

fn bracketed_symbol_to_html(symbol_name: String) -> String {
  let symbol_name_escaped =
    symbol_name |> string.replace(each: " ", with: "-") |> string.lowercase
  "<span class=\"icon icon-"
  <> symbol_name_escaped
  <> "\">"
  <> symbol_name
  <> "</span>"
}
