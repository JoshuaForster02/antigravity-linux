project('flynn-compositor', 'c',
  version: '1.0',
  default_options: ['c_std=c11', 'warning_level=2'])

cc = meson.get_compiler('c')

wlroots  = dependency('wlroots',       version: '>=0.17')
wayland  = dependency('wayland-server')
xkb      = dependency('xkbcommon')
glesv2   = dependency('glesv2',        required: false)
egl      = dependency('egl',           required: false)
pixman   = dependency('pixman-1')
libdrm   = dependency('libdrm')

srcs = files(
  'src/main.c',
  'src/wm.c',
  'src/renderer.c',
  'src/shader.c',
  'src/ipc.c',
)

deps = [wlroots, wayland, xkb, pixman, libdrm]
if glesv2.found() and egl.found()
  deps += [glesv2, egl]
  add_project_arguments('-DHAVE_GLES2', language: 'c')
endif

executable('flynn-compositor', srcs,
  dependencies: deps,
  include_directories: 'include',
  install: true)
