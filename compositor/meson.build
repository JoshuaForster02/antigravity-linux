project('flynn-compositor', 'c',
    version: '1.0',
    default_options: [
        'c_std=c11',
        'warning_level=2',
        'buildtype=release',
    ]
)

cc = meson.get_compiler('c')

# ── Dependencies ──────────────────────────────────────────────────────────────
wlroots     = dependency('wlroots',       version: '>= 0.17')
wayland_srv = dependency('wayland-server')
xkbcommon   = dependency('xkbcommon')
pixman      = dependency('pixman-1')
libinput    = dependency('libinput')
libdrm      = dependency('libdrm')
glesv2      = dependency('glesv2')
egl         = dependency('egl')
math        = cc.find_library('m', required: false)

# ── Shader directory ──────────────────────────────────────────────────────────
shader_dir = get_option('prefix') / 'share' / 'flynn-compositor' / 'shaders'
add_project_arguments(
    '-DSHADER_DIR="' + shader_dir + '"',
    language: 'c'
)

# ── Sources ───────────────────────────────────────────────────────────────────
src = files(
    'src/main.c',
    'src/shader.c',
    'src/renderer.c',
    'src/wm.c',
    'src/ipc.c',
)

# ── Executable ────────────────────────────────────────────────────────────────
executable('flynn-compositor',
    sources: src,
    dependencies: [
        wlroots, wayland_srv, xkbcommon,
        pixman, libinput, libdrm,
        glesv2, egl, math,
    ],
    include_directories: include_directories('include'),
    install: true,
)

# ── Install shaders ───────────────────────────────────────────────────────────
install_data(
    'shaders/tron-grid.vert',
    'shaders/tron-grid.frag',
    'shaders/glow-border.frag',
    install_dir: shader_dir,
)

# ── Install systemd service ───────────────────────────────────────────────────
systemd = dependency('systemd', required: false)
if systemd.found()
    systemd_user_dir = systemd.get_variable('systemduserunitdir')
    configure_file(
        input:  'flynn-compositor.service.in',
        output: 'flynn-compositor.service',
        configuration: {
            'BINDIR': get_option('prefix') / 'bin',
        }
    )
    install_data(
        meson.current_build_dir() / 'flynn-compositor.service',
        install_dir: systemd_user_dir,
    )
endif
