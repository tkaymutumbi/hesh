-- Hesh standalone device windows.
-- The em-dash title suffix is unique to child device hosts, so the main Hesh
-- workspace window remains governed by the normal layout.
o.window({ title = ".* — Hesh$" }, {
  float = true,
  center = true,
  -- Keep the preview crisp while retaining compositor borders and shadows.
  tag = "-default-opacity",
  opacity = "1 1",
  no_blur = true,
  no_dim = true,
  -- A window opened for an AI agent must not take focus or move the pointer.
  no_initial_focus = true,
})

-- The main shell also owns the embedded preview. Keep it opaque so the
-- compositor does not blend browser pixels with windows behind Hesh.
o.window({ title = "^Hesh$" }, {
  tag = "-default-opacity",
  opacity = "1 1",
})

-- The phone menu opens at the pointer.
o.window({ title = "^Hesh phone menu — Hesh$" }, {
  float = true,
  center = false,
  move = "cursor_x cursor_y",
  no_anim = true,
  no_dim = true,
})

-- Right-click on a phone mirror opens the Hesh menu. The click still reaches
-- scrcpy, which ignores it (see --mouse-bind in AndroidDevice).
hl.bind("mouse:273", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/hesh-phone-menu"), { non_consuming = true })
