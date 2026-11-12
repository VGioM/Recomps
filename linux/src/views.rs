//! L'interface de Recomps : barre latérale (bibliothèque, filtres, dossiers),
//! grille de jaquettes ou liste, fiche du jeu à droite. Les clics deviennent des
//! actions, appliquées une fois l'image dessinée.

use crate::app::App;
use crate::common::images::{Size, Source};
use crate::common::{icons, sys, theme, ui};
use crate::model::{self, Recomp, Status};
use egui::{Align, Align2, Color32, Layout, Rect, RichText, Sense, Stroke, Ui, Vec2};

enum Act {
    Scope(String),
    Select(Option<String>),
    Download(String, &'static str),
    Cancel(String, &'static str),
    Launch(String, &'static str),
    Reveal(std::path::PathBuf),
    Open(String),
    ChooseFolder(&'static str),
    OpenFolder(&'static str),
    UpdateAll,
    StopAll,
    Refresh,
    LoadNotes(String),
}

pub fn show(app: &mut App, ctx: &egui::Context) {
    let p = app.p;
    let mut acts = vec![];
    ctx.input(|i| {
        if i.modifiers.command && i.key_pressed(egui::Key::R) { acts.push(Act::Refresh); }
        if i.modifiers.command && i.key_pressed(egui::Key::F) { app.focus_search = true; }
        if i.key_pressed(egui::Key::Escape) && app.confirm_red.is_none() { acts.push(Act::Select(None)); }
    });
    let list = model::filtered(&app.apps, &model::Filter { scope: &app.scope, console: &app.console, genre: &app.genre, system: &app.system,
        search: &app.search, sort: &app.settings.string("sort") }, &app.state());

    egui::SidePanel::left("side").resizable(false).exact_width(250.0)
        .frame(egui::Frame::new().fill(p.sidebar).inner_margin(egui::Margin { left: 10, right: 10, top: 12, bottom: 10 }).stroke(Stroke::new(1.0_f32, p.hairline)))
        .show(ctx, |ui| sidebar(app, ui, &mut acts));
    egui::TopBottomPanel::top("tb").exact_height(54.0)
        .frame(egui::Frame::new().fill(p.toolbar).inner_margin(egui::Margin::symmetric(16, 8)).stroke(Stroke::new(1.0_f32, p.hairline)))
        .show(ctx, |ui| toolbar(app, ui, list.len(), &mut acts));
    if let Some(id) = app.selection.clone() {
        if let Some(a) = app.app(&id).cloned() {
            egui::SidePanel::right("detail").resizable(false).exact_width(420.0)
                .frame(egui::Frame::new().fill(p.panel).stroke(Stroke::new(1.0_f32, p.hairline)))
                .show(ctx, |ui| egui::ScrollArea::vertical().auto_shrink(false).show(ui, |ui| detail(app, ui, &a, &mut acts)));
        }
    }
    egui::CentralPanel::default().frame(egui::Frame::new().fill(p.content)).show(ctx, |ui| {
        banner(app, ui, &mut acts);
        if list.is_empty() {
            ui.centered_and_justified(|ui| ui.label(RichText::new(if app.apps.is_empty() { "Chargement du catalogue…" } else { "Aucun jeu ne correspond." }).color(p.muted)));
        } else if app.settings.bool("grid") { grid(app, ui, &list, &mut acts); } else { rows(app, ui, &list, &mut acts); }
    });

    // L'analyse du site a signalé ce fichier : on demande avant.
    if let Some((id, sys)) = app.confirm_red.clone() {
        let mut go = false;
        let close = ui::sheet(ctx, "red", 400.0, |ui| {
            ui.label(RichText::new("L'analyse antivirus du site a signalé ce fichier.").font(theme::bold(15.0)));
            ui.label("Vérifie le dépôt du projet avant de l'ouvrir.");
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                if ui.add(egui::Button::new(RichText::new("Télécharger quand même").color(Color32::WHITE)).fill(Color32::from_rgb(200, 60, 60))).clicked() { go = true; }
                ui.button("Annuler").clicked()
            }).inner || go
        });
        if go { let s = model::SYSTEMS.iter().find(|x| x.0 == sys).map(|x| x.0).unwrap_or("linux"); acts.push(Act::Download(id, s)); }
        if close || go { app.confirm_red = None; }
    }

    for a in acts {
        match a {
            Act::Scope(s) => app.scope = s,
            Act::Select(id) => { if let Some(i) = &id { app.load_notes(ctx, i); } app.selection = id; }
            Act::Download(id, s) => app.download(ctx, &id, s),
            Act::Cancel(id, s) => app.cancel(&id, s),
            Act::Launch(id, s) => app.launch(&id, s),
            Act::Reveal(p) => sys::reveal(&p),
            Act::Open(u) => sys::open_url(&u),
            Act::ChooseFolder(s) => app.choose_folder(s),
            Act::OpenFolder(s) => { let f = app.folder(s); let _ = std::fs::create_dir_all(&f); sys::open_path(&f); }
            Act::UpdateAll => app.update_all(ctx),
            Act::StopAll => app.stop_all(),
            Act::Refresh => app.refresh_all(ctx),
            Act::LoadNotes(id) => app.load_notes(ctx, &id),
        }
    }
}

/// Le téléchargement, si le fichier n'a pas été signalé ; sinon la question d'abord.
fn want(app: &App, a: &Recomp, sys: &'static str, acts: &mut Vec<Act>) -> bool {
    let red = a.files.get(sys).and_then(|f| f.scan.as_deref()) == Some("red");
    if !red { acts.push(Act::Download(a.id.clone(), sys)); }
    let _ = app;
    red
}

// ── Barre latérale ────────────────────────────────────────────────────────

fn sidebar(app: &mut App, ui: &mut Ui, acts: &mut Vec<Act>) {
    let p = app.p;
    ui.horizontal(|ui| {
        ui.add(egui::Image::from_bytes("bytes://recomps-icon.png", include_bytes!("../resources/icon.png").as_slice()).fit_to_exact_size(Vec2::splat(26.0)));
        ui.label(RichText::new("Recomps").font(theme::bold(16.0)));
    });
    egui::ScrollArea::vertical().auto_shrink(false).max_height(ui.available_height() - 60.0).show(ui, |ui| {
        ui::section_title(ui, &p, "Bibliothèque");
        let st = app.state();
        let now = sys::now_ms();
        for (id, label, icon) in model::SCOPES {
            let n = app.apps.iter().filter(|a| st.in_scope(a, id, now)).count();
            if ui::side_row(ui, &p, icon, label, Some(n.to_string()), None, app.scope == *id).clicked() { acts.push(Act::Scope(id.to_string())); }
        }
        ui::section_title(ui, &p, "Filtres");
        let mut consoles: Vec<(String, usize)> = vec![];
        for a in &app.apps { let o = a.origin.clone().unwrap_or("other".into()); match consoles.iter_mut().find(|c| c.0 == o) { Some(c) => c.1 += 1, None => consoles.push((o, 1)) } }
        consoles.sort_by(|a, b| b.1.cmp(&a.1));
        let mut genres: Vec<(String, usize)> = vec![];
        for a in &app.apps { let g = a.genre.clone().unwrap_or("other".into()); match genres.iter_mut().find(|c| c.0 == g) { Some(c) => c.1 += 1, None => genres.push((g, 1)) } }
        genres.sort_by(|a, b| b.1.cmp(&a.1));
        let row = |ui: &mut Ui, label: &str, add: &mut dyn FnMut(&mut Ui)| {
            ui.horizontal(|ui| { ui.label(RichText::new(label).size(12.0).color(p.muted)); ui.with_layout(Layout::right_to_left(Align::Center), |ui| add(ui)); });
        };
        let origins = app.origins.clone();
        let console_label = if app.console.is_empty() { "Toutes".to_string() } else { origins.get(&app.console).cloned().unwrap_or(app.console.clone()) };
        row(ui, "Console", &mut |ui| { egui::ComboBox::from_id_salt("console").width(140.0).selected_text(&console_label).show_ui(ui, |ui| {
            ui.selectable_value(&mut app.console, String::new(), "Toutes");
            for (id, n) in &consoles { ui.selectable_value(&mut app.console, id.clone(), format!("{} ({n})", origins.get(id).cloned().unwrap_or(id.clone()))); }
        }); });
        let genre_label = if app.genre.is_empty() { "Tous".into() } else { model::genre_fr(&app.genre).unwrap_or(&app.genre).to_string() };
        row(ui, "Genre", &mut |ui| { egui::ComboBox::from_id_salt("genre").width(140.0).selected_text(&genre_label).show_ui(ui, |ui| {
            ui.selectable_value(&mut app.genre, String::new(), "Tous");
            for (id, n) in &genres { ui.selectable_value(&mut app.genre, id.clone(), format!("{} ({n})", model::genre_fr(id).unwrap_or(id))); }
        }); });
        let sys_label = if app.system.is_empty() { "Tous" } else { model::sys_label(&app.system) };
        row(ui, "Système", &mut |ui| { egui::ComboBox::from_id_salt("sys").width(140.0).selected_text(sys_label).show_ui(ui, |ui| {
            ui.selectable_value(&mut app.system, String::new(), "Tous");
            for (id, l, _) in model::SYSTEMS { ui.selectable_value(&mut app.system, id.to_string(), *l); }
        }); });
        let mut sort = app.settings.string("sort");
        let sort_label = model::SORTS.iter().find(|s| s.0 == sort).map(|s| s.1).unwrap_or("Nom");
        row(ui, "Tri", &mut |ui| { egui::ComboBox::from_id_salt("sort").width(140.0).selected_text(sort_label).show_ui(ui, |ui| {
            for (id, l) in model::SORTS { ui.selectable_value(&mut sort, id.to_string(), *l); }
        }); });
        if sort != app.settings.string("sort") { app.settings.set("sort", sort); }
        if (!app.console.is_empty() || !app.genre.is_empty() || !app.system.is_empty()) && ui.link(RichText::new("Effacer les filtres").color(p.accent)).clicked() {
            app.console.clear(); app.genre.clear(); app.system.clear();
        }
        ui::section_title(ui, &p, "Dossiers des jeux");
        for (id, label, icon) in model::SYSTEMS {
            let f = app.folder(id);
            let comps: Vec<String> = f.components().map(|c| c.as_os_str().to_string_lossy().to_string()).filter(|c| c != "/").collect();
            let short = if comps.len() > 3 { format!("…/{}", comps[comps.len() - 3..].join("/")) } else { f.display().to_string() };
            let (rect, resp) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 38.0), Sense::click());
            if resp.hovered() { ui.painter().rect_filled(rect, 7, Color32::from_white_alpha(12)); }
            icons::image(icon, 16.0, p.accent).paint_at(ui, Rect::from_center_size(egui::pos2(rect.left() + 16.0, rect.center().y), Vec2::splat(16.0)));
            ui::text_in(ui, Rect::from_min_size(egui::pos2(rect.left() + 34.0, rect.top() + 3.0), Vec2::new(rect.width() - 40.0, 17.0)), label, theme::regular(13.0), p.text);
            ui::text_in(ui, Rect::from_min_size(egui::pos2(rect.left() + 34.0, rect.top() + 21.0), Vec2::new(rect.width() - 40.0, 14.0)), &short, theme::regular(10.5), p.muted);
            let resp = resp.on_hover_text(format!("{}\nClic : choisir un autre dossier · clic droit : plus", f.display()));
            if resp.clicked() { acts.push(Act::ChooseFolder(id)); }
            resp.context_menu(|ui| {
                if ui.button("Choisir…").clicked() { acts.push(Act::ChooseFolder(id)); ui.close_menu(); }
                if ui.button("Ouvrir le dossier").clicked() { acts.push(Act::OpenFolder(id)); ui.close_menu(); }
            });
        }
    });
    ui.with_layout(Layout::bottom_up(Align::LEFT), |ui| {
        ui.label(RichText::new("Données : recomplauncher.com").size(10.5).color(p.muted));
        if let Some(u) = &app.updated { ui.label(RichText::new(format!("Catalogue du {}", model::day(Some(u)))).size(10.5).color(p.muted)); }
        if let Some(e) = &app.error { ui.label(RichText::new(e).size(10.5).color(p.warm)); }
    });
}

// ── Barre d'outils ────────────────────────────────────────────────────────

fn update_all_button(app: &App, ui: &mut Ui, acts: &mut Vec<Act>) {
    let p = app.p;
    if let Some((done, total)) = *app.updating.lock().unwrap() {
        ui.add(egui::Spinner::new().size(14.0));
        ui.label(RichText::new(format!("Mise à jour {}/{total}", (done + 1).min(total))).size(12.0));
        if ui.button("Arrêter").clicked() { acts.push(Act::StopAll); }
    } else {
        let n = app.state().outdated(&app.apps).len();
        if n > 0 && ui::primary_icon(ui, &p, "downCircle", &format!("Tout mettre à jour ({n})"), false)
            .on_hover_text("Télécharge la dernière version de chaque jeu marqué « Mise à jour », l'un après l'autre").clicked() { acts.push(Act::UpdateAll); }
    }
}

fn toolbar(app: &mut App, ui: &mut Ui, count: usize, acts: &mut Vec<Act>) {
    let p = app.p;
    ui.horizontal_centered(|ui| {
        ui.vertical(|ui| {
            ui.spacing_mut().item_spacing.y = 0.0;
            ui.label(RichText::new(model::SCOPES.iter().find(|s| s.0 == app.scope).map(|s| s.1).unwrap_or("")).font(theme::bold(15.0)));
            ui.label(RichText::new(format!("{count} jeu{}", if count > 1 { "x" } else { "" })).size(11.5).color(p.muted));
        });
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            ui.menu_image_button(icons::image("more", 17.0, p.text), |ui| {
                if ui.button(crate::common::selfupdate::MENU_TITLE).clicked() { app.update.check_now(ui.ctx()); ui.close_menu(); }
                let mut auto = crate::common::selfupdate::SelfUpdate::automatic(&app.settings);
                if ui::check(ui, &p, &mut auto, crate::common::selfupdate::AUTO_TITLE).changed() { crate::common::selfupdate::SelfUpdate::set_automatic(&mut app.settings, auto); }
                ui.label(RichText::new(format!("Version {}", app.update.version())).size(11.5).color(p.muted));
            });
            let focus = std::mem::take(&mut app.focus_search);
            ui::search_field(ui, &p, &mut app.search, "Jeu, auteur, tag…", 220.0, focus);
            if app.loading { ui.add(egui::Spinner::new().size(16.0)); }
            else if ui::icon_button(ui, &p, "refresh", 17.0, "Actualiser le catalogue, les dossiers et les notes de version (Ctrl+R)").clicked() { acts.push(Act::Refresh); }
            let grid = app.settings.bool("grid");
            if ui.add(egui::Button::image(icons::image("list", 16.0, if grid { p.muted } else { p.text })).selected(!grid)).on_hover_text("Liste").clicked() { app.settings.set("grid", false); }
            if ui.add(egui::Button::image(icons::image("grid", 16.0, if grid { p.text } else { p.muted })).selected(grid)).on_hover_text("Grille").clicked() { app.settings.set("grid", true); }
            update_all_button(app, ui, acts);
        });
    });
}

fn banner(app: &App, ui: &mut Ui, acts: &mut Vec<Act>) {
    let o = app.state().outdated(&app.apps);
    let updating = app.updating.lock().unwrap().is_some();
    if app.scope != "updates" || (o.is_empty() && !updating) { return; }
    let p = app.p;
    egui::Frame::new().fill(p.panel2).corner_radius(16).stroke(Stroke::new(1.0_f32, p.accent.gamma_multiply(0.35))).inner_margin(16).outer_margin(egui::Margin { left: 22, right: 22, top: 18, bottom: 0 }).show(ui, |ui| {
        ui.horizontal(|ui| {
            ui.add(icons::image("downCircle", 26.0, p.accent));
            ui.vertical(|ui| {
                ui.label(RichText::new(if updating { "Mise à jour en cours…".to_string() } else { format!("{} mise{} à jour disponible{}", o.len(), if o.len() > 1 { "s" } else { "" }, if o.len() > 1 { "s" } else { "" }) }).font(theme::bold(14.0)));
                let names: Vec<String> = o.iter().map(|(i, s)| format!("{} ({})", app.apps[*i].name, model::sys_label(s))).collect();
                ui.add(egui::Label::new(RichText::new(names.join(" · ")).size(11.5).color(p.muted)).truncate());
            });
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| update_all_button(app, ui, acts));
        });
    });
}

fn pill(ui: &Ui, p: &theme::Palette, pos: egui::Pos2, anchor: Align2, st: Status, compact: bool) {
    let (text, icon, color) = match st {
        Status::UpToDate => ("À jour", "check", p.ok), Status::Outdated => ("Mise à jour", "download", p.warm), Status::Unknown => ("Présent", "question", p.muted), Status::None => return,
    };
    let g = ui.painter().layout_no_wrap(if compact { String::new() } else { text.into() }, theme::bold(11.0), color);
    let size = Vec2::new(g.size().x + if compact { 22.0 } else { 30.0 }, 20.0);
    let r = anchor.anchor_size(pos, size);
    ui.painter().rect(r, 99, Color32::from_rgba_premultiplied(11, 18, 32, 217), Stroke::new(1.0_f32, color.gamma_multiply(0.6)), egui::StrokeKind::Inside);
    icons::image(icon, 10.0, color).paint_at(ui, Rect::from_center_size(egui::pos2(r.left() + 11.0, r.center().y), Vec2::splat(10.0)));
    ui.painter().galley(egui::pos2(r.left() + 20.0, r.center().y - g.size().y / 2.0), g, color);
}

/// Le bouton pour télécharger sans ouvrir la fiche ; les autres systèmes dans le petit menu à côté.
fn quick(app: &App, ui: &mut Ui, a: &Recomp, compact: bool, acts: &mut Vec<Act>) -> bool {
    let p = app.p;
    let syss = a.sys_list();
    if a.is_soon() || syss.is_empty() { return false; }
    let dls = app.downloads.lock().unwrap();
    if let Some(d) = syss.iter().find_map(|s| dls.get(&App::key(&a.id, s))) {
        let frac = if d.total > 0 { d.done as f32 / d.total as f32 } else { 0.0 };
        ui.add(egui::ProgressBar::new(frac).desired_width(if compact { 40.0 } else { 100.0 }).desired_height(6.0)).on_hover_text(format!("Téléchargement : {} %", (frac * 100.0) as i32));
        return false;
    }
    drop(dls);
    let st = app.state();
    let Some(pref) = st.preferred(a) else { return false };
    let upd = st.status(a, pref) == Status::Outdated;
    let red = a.files.get(pref).and_then(|f| f.scan.as_deref()) == Some("red");
    let mut clicked = false;
    ui.horizontal(|ui| {
        ui.spacing_mut().item_spacing.x = 2.0;
        let label = if compact { String::new() } else if upd { "Mettre à jour".into() } else { model::sys_label(pref).into() };
        let b = egui::Button::image_and_text(icons::image(if upd { "sync" } else { "download" }, 11.0, p.on_accent), RichText::new(label).color(p.on_accent).size(11.5).strong())
            .fill(p.accent).corner_radius(99).min_size(Vec2::new(0.0, 22.0));
        let r = ui.add_enabled(!red, b).on_hover_text(if red { "L'analyse du site a signalé ce fichier : télécharge-le depuis la fiche".to_string() } else { format!("{} pour {}", if upd { "Mettre à jour" } else { "Télécharger" }, model::sys_label(pref)) });
        if r.clicked() { acts.push(Act::Download(a.id.clone(), pref)); clicked = true; }
        let others: Vec<&'static str> = syss.iter().copied().filter(|s| *s != pref).collect();
        if !others.is_empty() {
            let m = ui.menu_image_button(icons::image("chevronDown", 12.0, p.muted), |ui| {
                for s in &others {
                    let red = a.files.get(*s).and_then(|f| f.scan.as_deref()) == Some("red");
                    if ui.add_enabled(!red, egui::Button::new(format!("{} pour {}", if st.status(a, s) == Status::Outdated { "Mettre à jour" } else { "Télécharger" }, model::sys_label(s)))).clicked() {
                        acts.push(Act::Download(a.id.clone(), s)); ui.close_menu();
                    }
                }
            });
            if m.response.clicked() { clicked = true; }
        }
    });
    clicked
}

fn subtitle(app: &App, a: &Recomp) -> String {
    [a.origin.as_ref().map(|o| app.origins.get(o).cloned().unwrap_or(o.clone())), a.genre.as_deref().and_then(model::genre_fr).map(String::from)]
        .into_iter().flatten().collect::<Vec<_>>().join(" · ")
}

fn grid(app: &mut App, ui: &mut Ui, list: &[usize], acts: &mut Vec<Act>) {
    let p = app.p;
    let (pad, gap) = (22.0, 18.0);
    let width = ui.available_width() - 2.0 * pad;
    let cols = ((width + gap) / (148.0 + gap)).floor().max(1.0) as usize;
    let cw = ((width - gap * (cols as f32 - 1.0)) / cols as f32).min(190.0);
    let ch = cw * 1.5;
    let row_h = ch + 52.0;
    let mut hit = false;
    let scroll = egui::ScrollArea::vertical().auto_shrink(false).show_rows(ui, row_h, list.len().div_ceil(cols), |ui, range| {
        ui.add_space(22.0);
        for r in range {
            let (row, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), row_h), Sense::hover());
            for c in 0..cols {
                let Some(&i) = list.get(r * cols + c) else { break };
                let a = app.apps[i].clone();
                let x = row.left() + pad + c as f32 * (cw + gap);
                let cover = Rect::from_min_size(egui::pos2(x, row.top()), Vec2::new(cw, ch));
                let resp = ui.interact(cover, ui.id().with(("card", &a.id)), Sense::click());
                let selected = app.selection.as_deref() == Some(a.id.as_str());
                let hovered = resp.hovered();
                let draw = if hovered { cover.expand(2.0) } else { cover };
                ui::shadow(ui, draw, 14, selected);
                let src = a.cover.clone().or(a.icon.clone()).map(Source::Url);
                ui::cover(ui, &mut app.images, draw, src.as_ref(), &a.name, "gamepad", 14, Size::Thumb, false);
                // Le dégradé du bas, pour lire les systèmes et la version.
                let mut m = egui::Mesh::default();
                let half = Rect::from_min_max(egui::pos2(draw.left(), draw.center().y), draw.max);
                for (pt, c) in [(half.left_top(), Color32::TRANSPARENT), (half.right_top(), Color32::TRANSPARENT), (half.right_bottom(), Color32::from_rgba_premultiplied(9, 15, 27, 217)), (half.left_bottom(), Color32::from_rgba_premultiplied(9, 15, 27, 217))] { m.colored_vertex(pt, c); }
                m.add_triangle(0, 1, 2); m.add_triangle(0, 2, 3);
                ui.painter().add(egui::Shape::mesh(m));
                let mut sx = draw.left() + 9.0;
                for s in a.sys_list() { icons::image(model::sys_icon(s), 11.0, Color32::from_white_alpha(217)).paint_at(ui, Rect::from_min_size(egui::pos2(sx, draw.bottom() - 19.0), Vec2::splat(11.0))); sx += 16.0; }
                if a.is_soon() { ui.painter().text(draw.right_bottom() + Vec2::new(-8.0, -13.0), Align2::RIGHT_CENTER, "Bientôt", theme::bold(10.5), p.accent); }
                else if let Some(v) = &a.version { ui.painter().text(draw.right_bottom() + Vec2::new(-8.0, -13.0), Align2::RIGHT_CENTER, model::norm(Some(v)).unwrap_or(v.clone()), theme::regular(10.5), Color32::from_white_alpha(204)); }
                pill(ui, &p, draw.right_top() + Vec2::new(-7.0, 7.0), Align2::RIGHT_TOP, app.state().overall(&a), true);
                ui.painter().rect_stroke(draw, 14, if selected { Stroke::new(2.0_f32, p.accent) } else { Stroke::new(1.0_f32, if hovered { p.hairline_strong } else { p.hairline }) }, egui::StrokeKind::Inside);
                // Sous la jaquette : nom, console, bouton rapide.
                let under = Rect::from_min_size(egui::pos2(x, cover.bottom() + 7.0), Vec2::new(cw, 36.0));
                let mut child = ui.new_child(egui::UiBuilder::new().max_rect(under).layout(Layout::left_to_right(Align::Center)));
                let tw = cw - 70.0;
                ui::text_in(&child, Rect::from_min_size(under.min, Vec2::new(tw.max(60.0), 17.0)), &a.name, theme::bold(13.0), p.text);
                ui::text_in(&child, Rect::from_min_size(under.min + Vec2::new(0.0, 18.0), Vec2::new(tw.max(60.0), 15.0)), &subtitle(app, &a), theme::regular(11.5), p.muted);
                child.with_layout(Layout::right_to_left(Align::Center), |ui| { if quick(app, ui, &a, true, acts) { hit = true; } });
                if resp.clicked() { acts.push(Act::Select(Some(a.id.clone()))); hit = true; }
            }
        }
        ui.add_space(30.0);
    });
    // Un clic dans le vide de la grille ferme la fiche.
    if ui.interact(scroll.inner_rect, ui.id().with("bg"), Sense::click()).clicked() && !hit { acts.push(Act::Select(None)); }
}

fn rows(app: &mut App, ui: &mut Ui, list: &[usize], acts: &mut Vec<Act>) {
    let p = app.p;
    egui::ScrollArea::vertical().auto_shrink(false).show_rows(ui, 58.0, list.len(), |ui, range| {
        ui.add_space(14.0);
        for k in range {
            let a = app.apps[list[k]].clone();
            let (rect, resp) = ui.allocate_exact_size(Vec2::new(ui.available_width() - 28.0, 56.0), Sense::click());
            let rect = rect.translate(Vec2::new(14.0, 0.0));
            if app.selection.as_deref() == Some(a.id.as_str()) { ui.painter().rect(rect, 12, p.panel2, Stroke::new(1.0_f32, p.accent.gamma_multiply(0.6)), egui::StrokeKind::Inside); }
            let ic = Rect::from_min_size(rect.min + Vec2::new(12.0, 8.0), Vec2::splat(40.0));
            let src = a.icon.clone().map(Source::Url);
            ui::cover(ui, &mut app.images, ic, src.as_ref(), &a.name, "gamepad", 10, Size::Thumb, false);
            let right = 12.0 + 130.0 + 110.0 + 90.0 + 60.0;
            let tw = rect.width() - 64.0 - right;
            ui::text_in(ui, Rect::from_min_size(rect.min + Vec2::new(64.0, 11.0), Vec2::new(tw, 17.0)), &a.name, theme::bold(13.0), p.text);
            ui::text_in(ui, Rect::from_min_size(rect.min + Vec2::new(64.0, 30.0), Vec2::new(tw, 15.0)), &subtitle(app, &a), theme::regular(11.5), p.muted);
            let mut sx = rect.right() - right + 8.0;
            for s in a.sys_list() { icons::image(model::sys_icon(s), 11.0, p.text).paint_at(ui, Rect::from_min_size(egui::pos2(sx, rect.center().y - 5.5), Vec2::splat(11.0))); sx += 16.0; }
            let ver = if a.is_soon() { "Bientôt".into() } else { a.version.as_deref().map(|v| model::norm(Some(v)).unwrap_or(v.into())).unwrap_or_default() };
            ui.painter().text(egui::pos2(rect.right() - 12.0 - 130.0 - 110.0 - 8.0, rect.center().y), Align2::RIGHT_CENTER, ver, theme::regular(11.5), p.muted);
            pill(ui, &p, egui::pos2(rect.right() - 12.0 - 130.0 - 8.0, rect.center().y), Align2::RIGHT_CENTER, app.state().overall(&a), false);
            let mut child = ui.new_child(egui::UiBuilder::new().max_rect(Rect::from_min_size(egui::pos2(rect.right() - 142.0, rect.top()), Vec2::new(130.0, rect.height()))).layout(Layout::right_to_left(Align::Center)));
            let q = quick(app, &mut child, &a, false, acts);
            if resp.clicked() && !q { acts.push(Act::Select(Some(a.id.clone()))); }
        }
    });
}

// ── Fiche ─────────────────────────────────────────────────────────────────

fn sys_row(app: &mut App, ui: &mut Ui, a: &Recomp, s: &'static str, acts: &mut Vec<Act>) {
    let p = app.p;
    let st = app.state();
    let status = st.status(a, s);
    let k = App::key(&a.id, s);
    let dl = app.downloads.lock().unwrap().get(&k).cloned();
    let f = a.files.get(s).cloned();
    let local = st.local_path(a, s);
    let found_version = if st.inst(a, s).is_none() { app.found.get(&a.id).and_then(|m| m.get(s)).and_then(|f| f.version.clone()) } else { None };
    egui::Frame::new().fill(p.panel2).corner_radius(14).stroke(Stroke::new(1.0_f32, p.hairline)).inner_margin(12).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.horizontal(|ui| {
            ui.add(icons::image(model::sys_icon(s), 15.0, p.accent));
            ui.vertical(|ui| {
                ui.spacing_mut().item_spacing.y = 1.0;
                ui.label(RichText::new(model::sys_label(s)).font(theme::bold(13.0)));
                ui.add(egui::Label::new(RichText::new(f.as_ref().and_then(|f| f.name.clone()).or(a.pattern(s).map(String::from)).unwrap_or_default()).monospace().size(10.5).color(p.muted)).truncate());
            });
            let r = ui.min_rect();
            pill(ui, &p, egui::pos2(ui.max_rect().right(), r.center().y), Align2::RIGHT_CENTER, status, false);
        });
        if let Some(l) = &local {
            let name = l.file_name().unwrap_or_default().to_string_lossy().to_string();
            let v = found_version.as_ref().map(|v| format!(" · v{}", model::norm(Some(v)).unwrap_or(v.clone()))).unwrap_or_default();
            ui.horizontal(|ui| { ui.add(icons::image(if l.is_dir() { "folder" } else { "zip" }, 13.0, p.muted)); ui.add(egui::Label::new(RichText::new(format!("{name}{v}")).size(11.0).color(p.muted)).truncate()); });
        }
        if dl.is_none() { if let Some(e) = app.errors.get(&k) { ui.horizontal_wrapped(|ui| { ui.add(icons::image("warning", 13.0, p.warm)); ui.label(RichText::new(e).size(11.5).color(p.warm)); }); } }
        if let Some(d) = &dl {
            ui.add(egui::ProgressBar::new(if d.total > 0 { d.done as f32 / d.total as f32 } else { 0.0 }).desired_height(4.0));
            ui.label(RichText::new(if d.total > 0 { format!("{} / {}", sys::bytes(d.done), sys::bytes(d.total)) } else { "Préparation…".into() }).size(10.5).color(p.muted));
        }
        ui.horizontal(|ui| {
            if let Some(scan) = f.as_ref().and_then(|f| f.scan.clone()) {
                let (t, c) = match scan.as_str() { "green" => ("Analyse OK", p.ok), "yellow" => ("Analyse : à vérifier", p.warm), "red" => ("Analyse : alerte", Color32::from_rgb(255, 90, 90)), _ => ("Analyse en cours", p.muted) };
                ui.add(icons::image("shield", 11.0, c));
                ui.label(RichText::new(t).size(10.5).color(c));
            }
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                if dl.is_some() { if ui.button("Annuler").clicked() { acts.push(Act::Cancel(a.id.clone(), s)); } }
                else if status == Status::UpToDate { if ui.button("Retélécharger").clicked() && want(app, a, s, acts) { app.confirm_red = Some((a.id.clone(), s.into())); } }
                else if ui::primary(ui, &p, if status == Status::None { "Télécharger" } else { "Mettre à jour" }).clicked() && want(app, a, s, acts) { app.confirm_red = Some((a.id.clone(), s.into())); }
                if let Some(l) = &local {
                    if s == "linux" && ui::button_icon(ui, &p, "play", "Lancer").clicked() { acts.push(Act::Launch(a.id.clone(), s)); }
                    if ui::icon_button(ui, &p, "folder", 14.0, "Afficher dans le gestionnaire de fichiers").clicked() { acts.push(Act::Reveal(l.clone())); }
                }
            });
        });
    });
}

fn detail(app: &mut App, ui: &mut Ui, a: &Recomp, acts: &mut Vec<Act>) {
    let p = app.p;
    // L'image de tête, le nom et l'icône.
    let (hero, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 190.0), Sense::hover());
    let src = a.hero.clone().or(a.cover.clone()).map(Source::Url);
    ui::cover(ui, &mut app.images, hero, src.as_ref(), &a.name, "gamepad", 0, Size::Large, false);
    let mut m = egui::Mesh::default();
    for (pt, c) in [(hero.left_top(), Color32::TRANSPARENT), (hero.right_top(), Color32::TRANSPARENT), (hero.right_bottom(), p.panel), (hero.left_bottom(), p.panel)] { m.colored_vertex(pt, c); }
    m.add_triangle(0, 1, 2); m.add_triangle(0, 2, 3);
    ui.painter().add(egui::Shape::mesh(m));
    let ic = Rect::from_min_size(egui::pos2(hero.left() + 18.0, hero.bottom() - 62.0), Vec2::splat(58.0));
    let isrc = a.icon.clone().map(Source::Url);
    ui::cover(ui, &mut app.images, ic, isrc.as_ref(), &a.name, "gamepad", 14, Size::Thumb, false);
    ui::text_in(ui, Rect::from_min_size(egui::pos2(ic.right() + 12.0, ic.top() + 12.0), Vec2::new(hero.width() - 110.0, 24.0)), &a.name, theme::bold(20.0), p.text);
    if let Some(g) = a.game.as_ref().filter(|g| **g != a.name) { ui::text_in(ui, Rect::from_min_size(egui::pos2(ic.right() + 12.0, ic.top() + 38.0), Vec2::new(hero.width() - 110.0, 16.0)), g, theme::regular(12.5), p.muted); }

    egui::Frame::new().inner_margin(egui::Margin { left: 18, right: 18, top: 14, bottom: 22 }).show(ui, |ui| {
        let mut chips: Vec<String> = vec![];
        if let Some(o) = &a.origin { chips.push(app.origins.get(o).cloned().unwrap_or(o.clone())); }
        if let Some(g) = a.genre.as_deref().and_then(model::genre_fr) { chips.push(g.into()); }
        if let Some(au) = &a.author { chips.push(format!("par {au}")); }
        if let Some(l) = &a.license { chips.push(l.clone()); }
        match (a.status.as_deref(), a.archived) { (Some("ended"), _) => chips.push("arrêté".into()), (Some("paused"), _) => chips.push("en pause".into()), (_, true) => chips.push("archivé".into()), _ => {} }
        ui::chips(ui, &p, &chips);
        if !a.is_soon() {
            ui.horizontal(|ui| {
                let stat = |ui: &mut Ui, k: &str, v: String| { ui.vertical(|ui| { ui.spacing_mut().item_spacing.y = 1.0; ui.label(RichText::new(k).font(theme::bold(9.5)).color(p.muted)); ui.label(RichText::new(v).font(theme::bold(13.0))); }); ui.add_space(8.0); };
                stat(ui, "VERSION", a.version.as_deref().map(|v| model::norm(Some(v)).unwrap_or(v.into())).unwrap_or("?".into()));
                stat(ui, "SORTIE", model::day(a.released.as_deref()));
                if let Some(s) = a.size.as_ref().filter(|s| !s.is_empty()) { stat(ui, "TAILLE", s.clone()); }
                if let Some(d) = a.downloads { stat(ui, "TÉLÉCH.", if d >= 1000 { format!("{:.1} k", d as f64 / 1000.0).replace('.', ",") } else { d.to_string() }); }
            });
        }
        if matches!(a.status.as_deref(), Some("ended") | Some("paused")) || a.archived {
            let text = a.status_note.clone().unwrap_or_else(|| match a.status.as_deref() { Some("paused") => "Le développement est en pause.".into(), Some("ended") => "Le développeur a arrêté le projet : plus de mise à jour prévue.".into(), _ => "Dépôt archivé : plus de mise à jour prévue.".into() });
            ui.label(RichText::new(text).size(12.0).color(p.warm));
        }
        if let Some(b) = a.blurb.as_ref().filter(|b| !b.is_empty()) { ui.add(egui::Label::new(RichText::new(b).size(13.0)).wrap().selectable(true)); }
        if let Some(n) = a.needs.as_ref().filter(|n| !n.is_empty()) { ui.horizontal_top(|ui| { ui.add(icons::image("disc", 14.0, p.muted)); ui.add(egui::Label::new(RichText::new(n).size(12.0).color(p.muted)).wrap()); }); }
        if a.is_soon() {
            ui.horizontal(|ui| { ui.add(icons::image("clock", 15.0, p.muted)); ui.label(RichText::new("Pas encore de version téléchargeable.").color(p.muted)); });
        } else {
            caps(ui, &p, "TÉLÉCHARGER");
            for s in a.sys_list() { sys_row(app, ui, a, s, acts); }
        }
        if a.repo.is_some() && !a.is_soon() { changelog(app, ui, a, acts); }
        if !a.setup_steps.is_empty() {
            caps(ui, &p, "INSTALLATION");
            for (i, t) in a.setup_steps.iter().enumerate() {
                ui.horizontal_top(|ui| {
                    let (r, _) = ui.allocate_exact_size(Vec2::splat(18.0), Sense::hover());
                    ui.painter().circle_filled(r.center(), 9.0, p.accent);
                    ui.painter().text(r.center(), Align2::CENTER_CENTER, (i + 1).to_string(), theme::bold(11.0), p.on_accent);
                    ui.add(egui::Label::new(RichText::new(t).size(12.5)).wrap().selectable(true));
                });
            }
        }
        if !a.features.is_empty() {
            caps(ui, &p, "POINTS FORTS");
            for t in &a.features { ui.horizontal_top(|ui| { ui.add(icons::image("check", 13.0, p.accent)); ui.add(egui::Label::new(RichText::new(t).size(12.5)).wrap()); }); }
        }
        if let Some(s) = a.about.summary.as_ref().filter(|s| !s.is_empty()) { caps(ui, &p, "LE JEU"); ui.add(egui::Label::new(RichText::new(s).size(12.5).color(p.muted)).wrap().selectable(true)); }
        ui.add_space(4.0);
        ui.horizontal_wrapped(|ui| {
            if let Some(r) = &a.repo { if ui.button(if a.gitlab() { "GitLab" } else { "GitHub" }).clicked() { acts.push(Act::Open(format!("https://{}/{r}", if a.gitlab() { "gitlab.com" } else { "github.com" }))); } }
            if let Some(u) = a.report_url.as_ref().filter(|u| u.starts_with("https://")) { if ui.button("Signaler un problème").clicked() { acts.push(Act::Open(u.clone())); } }
            if ui.button("Page du site").clicked() { acts.push(Act::Open(format!("https://recomplauncher.com/pc/game/{}", crate::app::urlenc(&a.id)))); }
        });
    });
}

fn caps(ui: &mut Ui, p: &theme::Palette, t: &str) { ui.add_space(6.0); ui.label(RichText::new(t).font(theme::bold(10.5)).color(p.muted)); }

fn changelog(app: &mut App, ui: &mut Ui, a: &Recomp, acts: &mut Vec<Act>) {
    let p = app.p;
    caps(ui, &p, "NOTES DE VERSION");
    let repo = a.repo.clone().unwrap_or_default();
    let Some(rels) = app.notes.get(&repo).cloned() else {
        if let Some(e) = app.notes_error.get(&repo) { ui.label(RichText::new(e).size(12.0).color(p.warm)); }
        else { ui.horizontal(|ui| { ui.add(egui::Spinner::new().size(12.0)); ui.label(RichText::new("Chargement…").size(12.0).color(p.muted)); }); acts.push(Act::LoadNotes(a.id.clone())); }
        return;
    };
    // La version présente : celle téléchargée ici, sinon celle lue sur le fichier.
    let st = app.state();
    let mut lv: Option<String> = None;
    let mut ld: Option<i64> = None;
    for s in a.sys_list() { if let Some(i) = app.installed.get(&a.id).and_then(|m| m.get(s)) { lv = i.tag.clone().or(i.version.clone()); ld = Some(i.date); break; } }
    if lv.is_none() && ld.is_none() { for s in a.sys_list() { if let Some(f) = app.found.get(&a.id).and_then(|m| m.get(s)) { lv = f.version.clone(); ld = Some(f.date); break; } } }
    let _ = st;
    let mine = lv.as_ref().and_then(|v| rels.iter().position(|r| model::norm(Some(v)) == model::norm(Some(&r.tag_name)) || model::norm(Some(v)) == model::norm(r.name.as_deref())));
    let is_new = |i: usize, r: &crate::app::Release| -> bool {
        if lv.is_none() && ld.is_none() { return false; }
        if let Some(m) = mine { return i < m; }
        match (ld, r.published_at.as_deref().and_then(|d| chrono::DateTime::parse_from_rfc3339(d).ok())) { (Some(l), Some(d)) => d.timestamp_millis() > l, _ => false }
    };
    if rels.is_empty() { ui.label(RichText::new("Aucune release publiée.").size(12.0).color(p.muted)); }
    let show_all = app.show_all.contains(&a.id);
    for (i, r) in rels.iter().enumerate().take(if show_all { rels.len() } else { 3 }) {
        let new = is_new(i, r);
        let key = format!("{}:{}", a.id, r.tag_name);
        let expanded = *app.expanded.get(&key).unwrap_or(&(i == 0));
        egui::Frame::new().fill(p.panel2).corner_radius(12).stroke(Stroke::new(1.0_f32, if new { p.accent.gamma_multiply(0.45) } else { p.hairline })).inner_margin(12).show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.horizontal(|ui| {
                ui.label(RichText::new(&r.tag_name).font(theme::bold(12.5)));
                if let Some(n) = r.name.as_ref().filter(|n| !n.is_empty() && **n != r.tag_name) { ui.add(egui::Label::new(RichText::new(n).size(12.0).color(p.muted)).truncate()); }
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if let Some(d) = &r.published_at { ui.label(RichText::new(model::day(Some(d))).size(11.0).color(p.muted)); }
                    let tag = |ui: &mut Ui, t: &str, c: Color32| { egui::Frame::new().fill(c.gamma_multiply(0.15)).corner_radius(99).inner_margin(egui::Margin::symmetric(6, 1)).show(ui, |ui| ui.label(RichText::new(t).size(10.0).strong().color(c))); };
                    if r.prerelease { tag(ui, "préversion", p.warm); }
                    if mine == Some(i) { tag(ui, "ta version", p.ok); }
                    if new { tag(ui, "nouveau", p.accent); }
                });
            });
            let lines = model::notes_lines(r.body.as_deref().unwrap_or(""));
            if !lines.is_empty() {
                let mut job = egui::text::LayoutJob::default();
                for (k, (t, b)) in lines.iter().enumerate() {
                    if k > 0 { job.append("\n", 0.0, egui::TextFormat { font_id: theme::regular(12.0), ..Default::default() }); }
                    job.append(t, 0.0, egui::TextFormat { font_id: if *b { theme::bold(12.0) } else { theme::regular(12.0) }, color: p.text.gamma_multiply(0.88), ..Default::default() });
                }
                job.wrap.max_width = ui.available_width();
                if !expanded { job.wrap.max_rows = 4; }
                ui.add(egui::Label::new(job).selectable(true));
                ui.horizontal(|ui| {
                    if ui.link(RichText::new(if expanded { "Réduire" } else { "Lire la suite" }).size(11.5).color(p.accent)).clicked() { app.expanded.insert(key.clone(), !expanded); }
                    if let Some(u) = &r.html_url { ui.with_layout(Layout::right_to_left(Align::Center), |ui| if ui.link(RichText::new(if u.contains("gitlab") { "Sur GitLab" } else { "Sur GitHub" }).size(11.5).color(p.muted)).clicked() { acts.push(Act::Open(u.clone())); }); }
                });
            }
        });
    }
    if rels.len() > 3 && ui.link(RichText::new(if show_all { "Moins".to_string() } else { format!("Toutes les versions ({})", rels.len()) }).size(12.0).color(p.accent)).clicked() {
        if show_all { app.show_all.remove(&a.id); } else { app.show_all.insert(a.id.clone()); }
    }
}
