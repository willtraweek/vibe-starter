//! The event loop: read a key, update the model, draw. It is generic over the
//! terminal backend and the event source, so tests drive the real loop with
//! ratatui's `TestBackend` and a scripted list of events.

use std::io;

use ratatui::Terminal;
use ratatui::backend::Backend;
use ratatui::crossterm::event::Event;

use crate::model::{Model, action_for};
use crate::view;

/// Draws, then handles `events` until the user quits or they run out, and
/// returns the final model. A resize draws again, at the terminal's new size.
///
/// # Errors
///
/// When drawing fails, or an event cannot be read.
pub fn run<B>(
    terminal: &mut Terminal<B>,
    events: impl IntoIterator<Item = io::Result<Event>>,
) -> io::Result<Model>
where
    B: Backend,
    B::Error: Send + Sync + 'static,
{
    let mut model = Model::default();
    draw(terminal, model)?;
    for event in events {
        let key = match event? {
            Event::Key(key) => key,
            // ratatui fits the screen to the terminal's size when it draws.
            Event::Resize(..) => {
                draw(terminal, model)?;
                continue;
            }
            _ => continue,
        };
        let Some(action) = action_for(key) else {
            continue;
        };
        model.update(action);
        if model.should_quit() {
            break;
        }
        draw(terminal, model)?;
    }
    Ok(model)
}

fn draw<B>(terminal: &mut Terminal<B>, model: Model) -> io::Result<()>
where
    B: Backend,
    B::Error: Send + Sync + 'static,
{
    terminal
        .draw(|frame| view::render(model, frame))
        .map_err(io::Error::other)?;
    Ok(())
}
