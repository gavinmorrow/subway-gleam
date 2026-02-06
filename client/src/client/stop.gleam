import lustre
import lustre/effect.{type Effect}
import shared/route/stop.{type Model, view}

pub fn app() -> Result(lustre.Runtime(Msg), lustre.Error) {
  let app = lustre.application(init, update, view)
  lustre.start(app, onto: "#app", with: Nil)
}

pub type Msg

fn init(_flags: Nil) -> #(Model(Msg), Effect(Msg)) {
  todo
}

fn update(model: Model(Msg), msg: Msg) -> a {
  todo
}
