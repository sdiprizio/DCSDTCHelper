declare_plugin("DCSDTCHelper", {
    installed = true,
    dirName = current_mod_path,
    displayName = _("DCS DTC Helper"),
    version = "0.1.0",
    state = "installed",
    info = _("VR virtual keyboard and DTC helper."),
    Options = {
        {
            name = "DCSDTCHelper",
            nameId = "DCSDTCHelper",
            dir = "Options",
            allow_in_simulation = true,
        },
    },
})

plugin_done()
