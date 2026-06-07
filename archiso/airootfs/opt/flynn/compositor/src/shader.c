/*
 * shader.c — OpenGL ES shader compilation helpers
 */
#include "flynn-compositor.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static GLuint compile_shader(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);

    GLint ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(s, 512, NULL, log);
        wlr_log(WLR_ERROR, "Shader compile error: %s", log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

bool shader_compile(flynn_shader_t *s,
                    const char *vert_src, const char *frag_src) {
    GLuint vert = compile_shader(GL_VERTEX_SHADER,   vert_src);
    GLuint frag = compile_shader(GL_FRAGMENT_SHADER, frag_src);
    if (!vert || !frag) return false;

    s->program = glCreateProgram();
    glAttachShader(s->program, vert);
    glAttachShader(s->program, frag);
    glLinkProgram(s->program);

    GLint ok;
    glGetProgramiv(s->program, GL_LINK_STATUS, &ok);
    glDeleteShader(vert);
    glDeleteShader(frag);

    if (!ok) {
        char log[512];
        glGetProgramInfoLog(s->program, 512, NULL, log);
        wlr_log(WLR_ERROR, "Shader link error: %s", log);
        return false;
    }

    s->loc_time       = glGetUniformLocation(s->program, "u_time");
    s->loc_resolution = glGetUniformLocation(s->program, "u_resolution");
    s->loc_glow       = glGetUniformLocation(s->program, "u_glow");
    s->loc_tex        = glGetUniformLocation(s->program, "u_tex");
    return true;
}

void shader_use(const flynn_shader_t *s) {
    glUseProgram(s->program);
}
