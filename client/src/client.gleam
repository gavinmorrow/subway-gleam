import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "body", Nil)

  Nil
}

type Model {
  Model
}

type Msg

fn init(_arg: Nil) -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    _ -> #(model, effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  todo
}
