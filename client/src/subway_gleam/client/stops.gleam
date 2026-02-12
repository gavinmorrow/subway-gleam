import lustre
import lustre/effect

import subway_gleam/shared/route/stops.{type Model, Model, view}

pub fn main() -> Result(lustre.Runtime(Msg), lustre.Error) {
  let model = Model

  let app = lustre.application(init, update, view)
  lustre.start(app, onto: "#app", with: model)
}

pub type Msg

fn init(flags: Model) -> #(Model, effect.Effect(Msg)) {
  #(flags, effect.none())
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  #(model, effect.none())
}
