//! Recomps pour Linux : catalogue des recomps PC de recomplauncher.com, avec
//! recherche, filtres, téléchargement (Windows, Mac, Linux) et suivi des
//! versions présentes dans un dossier par système.

mod app;
mod common;
mod model;
mod views;

fn main() -> eframe::Result {
    let icon = image::load_from_memory(include_bytes!("../resources/icon.png")).ok().map(|i| {
        let i = i.to_rgba8();
        let (w, h) = i.dimensions();
        egui::IconData { rgba: i.into_raw(), width: w, height: h }
    });
    let mut viewport = egui::ViewportBuilder::default()
        .with_title("Recomps").with_app_id("recomps").with_inner_size([1280.0, 820.0]).with_min_inner_size([980.0, 620.0]);
    if let Some(i) = icon { viewport = viewport.with_icon(i); }
    let options = eframe::NativeOptions { viewport, renderer: eframe::Renderer::Glow, ..Default::default() };
    eframe::run_native("Recomps", options, Box::new(|cc| Ok(Box::new(app::App::new(cc)))))
}
