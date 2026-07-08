use pm.make as make

export let name = "mesa-minimal"

export let ver = "24.2.8"

export let rel = "21"

export let deps = ["musl", "libdrm", "wayland-libs-client", "wayland-libs-server", "libffi"]

export let mkdeps = ["llvm-toolchain", "linux", "pkgconf", "libdrm", "wayland-dev", "libffi"]

export let sources = [p"files/source-marker.txt => ."]

export let checksums = ["2f848716fcc0bb55ee07c37ab374d8b8824dd38debcc0be4711b4930f1c67381"]

proc write_sources() [fs, error] {
  fs.write(
    p"laputa-egl.c",
    """#include <stddef.h>
#include <stdint.h>

typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLSurface;
typedef void *EGLContext;
typedef void *EGLClientBuffer;
typedef void *EGLNativeDisplayType;
typedef void *EGLNativeWindowType;
typedef void *EGLImage;
typedef int EGLint;
typedef unsigned int EGLBoolean;
typedef unsigned int EGLenum;

#define EGL_TRUE 1
#define EGL_FALSE 0
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_SUCCESS 0x3000
#define EGL_BAD_ALLOC 0x3003
#define EGL_BAD_DISPLAY 0x3008

static EGLint laputa_egl_error = EGL_SUCCESS;

EGLDisplay eglGetDisplay(EGLNativeDisplayType display_id)
{
    (void)display_id;
    return (EGLDisplay)(uintptr_t)1;
}

EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *native_display, const EGLint *attrib_list)
{
    (void)platform;
    (void)native_display;
    (void)attrib_list;
    return (EGLDisplay)(uintptr_t)1;
}

EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor)
{
    if (dpy == EGL_NO_DISPLAY) {
        laputa_egl_error = EGL_BAD_DISPLAY;
        return EGL_FALSE;
    }
    if (major != NULL)
        *major = 1;
    if (minor != NULL)
        *minor = 5;
    laputa_egl_error = EGL_SUCCESS;
    return EGL_TRUE;
}

EGLBoolean eglTerminate(EGLDisplay dpy)
{
    (void)dpy;
    return EGL_TRUE;
}

EGLBoolean eglBindAPI(EGLenum api)
{
    (void)api;
    return EGL_TRUE;
}

EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attrib_list, EGLConfig *configs, EGLint config_size, EGLint *num_config)
{
    (void)attrib_list;
    if (dpy == EGL_NO_DISPLAY) {
        laputa_egl_error = EGL_BAD_DISPLAY;
        return EGL_FALSE;
    }
    if (configs != NULL && config_size > 0)
        configs[0] = (EGLConfig)(uintptr_t)1;
    if (num_config != NULL)
        *num_config = 1;
    return EGL_TRUE;
}

EGLBoolean eglGetConfigs(EGLDisplay dpy, EGLConfig *configs, EGLint config_size, EGLint *num_config)
{
    return eglChooseConfig(dpy, NULL, configs, config_size, num_config);
}

EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config, EGLContext share_context, const EGLint *attrib_list)
{
    (void)config;
    (void)share_context;
    (void)attrib_list;
    if (dpy == EGL_NO_DISPLAY) {
        laputa_egl_error = EGL_BAD_DISPLAY;
        return EGL_NO_CONTEXT;
    }
    return (EGLContext)(uintptr_t)1;
}

EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx)
{
    (void)dpy;
    (void)ctx;
    return EGL_TRUE;
}

EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint *attrib_list)
{
    (void)config;
    (void)win;
    (void)attrib_list;
    if (dpy == EGL_NO_DISPLAY) {
        laputa_egl_error = EGL_BAD_DISPLAY;
        return EGL_NO_SURFACE;
    }
    return (EGLSurface)(uintptr_t)1;
}

EGLSurface eglCreatePlatformWindowSurface(EGLDisplay dpy, EGLConfig config, void *native_window, const EGLint *attrib_list)
{
    return eglCreateWindowSurface(dpy, config, native_window, attrib_list);
}

EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface)
{
    (void)dpy;
    (void)surface;
    return EGL_TRUE;
}

EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx)
{
    (void)dpy;
    (void)draw;
    (void)read;
    (void)ctx;
    return EGL_TRUE;
}

EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface)
{
    (void)dpy;
    (void)surface;
    return EGL_TRUE;
}

EGLBoolean eglQueryContext(EGLDisplay dpy, EGLContext ctx, EGLint attribute, EGLint *value)
{
    (void)dpy;
    (void)ctx;
    (void)attribute;
    if (value != NULL)
        *value = 0;
    return EGL_TRUE;
}

EGLBoolean eglQuerySurface(EGLDisplay dpy, EGLSurface surface, EGLint attribute, EGLint *value)
{
    (void)dpy;
    (void)surface;
    (void)attribute;
    if (value != NULL)
        *value = 0;
    return EGL_TRUE;
}

EGLint eglGetError(void)
{
    EGLint error = laputa_egl_error;
    laputa_egl_error = EGL_SUCCESS;
    return error;
}

EGLDisplay eglGetCurrentDisplay(void)
{
    return (EGLDisplay)(uintptr_t)1;
}

EGLContext eglGetCurrentContext(void)
{
    return (EGLContext)(uintptr_t)1;
}

EGLSurface eglGetCurrentSurface(EGLint readdraw)
{
    (void)readdraw;
    return (EGLSurface)(uintptr_t)1;
}

const char *eglQueryString(EGLDisplay dpy, EGLint name)
{
    (void)dpy;
    (void)name;
    return "Laputa minimal EGL";
}

void *eglGetProcAddress(const char *procname)
{
    (void)procname;
    return NULL;
}

EGLBoolean eglSwapInterval(EGLDisplay dpy, EGLint interval)
{
    (void)dpy;
    (void)interval;
    return EGL_TRUE;
}

EGLBoolean eglReleaseThread(void)
{
    return EGL_TRUE;
}
""",
  )?

  fs.write(
    p"laputa-gles2.c",
    """#include <stddef.h>
#include <stdint.h>

typedef unsigned int GLenum;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef void GLvoid;
typedef signed char GLbyte;
typedef short GLshort;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef float GLfloat;
typedef float GLclampf;
typedef ptrdiff_t GLsizeiptr;
typedef ptrdiff_t GLintptr;
typedef long long GLint64;
typedef char GLchar;

#define GL_VENDOR 0x1F00
#define GL_RENDERER 0x1F01
#define GL_VERSION 0x1F02
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#define GL_EXTENSIONS 0x1F03
#define GL_NO_ERROR 0
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5

const GLubyte *glGetString(GLenum name)
{
    switch (name) {
    case GL_VENDOR:
        return (const GLubyte *)"Laputa";
    case GL_RENDERER:
        return (const GLubyte *)"Laputa minimal GLES2";
    case GL_VERSION:
        return (const GLubyte *)"OpenGL ES 2.0 Laputa";
    case GL_SHADING_LANGUAGE_VERSION:
        return (const GLubyte *)"OpenGL ES GLSL ES 1.00";
    case GL_EXTENSIONS:
        return (const GLubyte *)"";
    default:
        return (const GLubyte *)"";
    }
}

GLenum glGetError(void) { return GL_NO_ERROR; }
void glGetIntegerv(GLenum pname, GLint *data) { (void)pname; if (data != NULL) *data = 0; }
void glGetFloatv(GLenum pname, GLfloat *data) { (void)pname; if (data != NULL) *data = 0.0f; }
void glViewport(GLint x, GLint y, GLsizei width, GLsizei height) { (void)x; (void)y; (void)width; (void)height; }
void glScissor(GLint x, GLint y, GLsizei width, GLsizei height) { (void)x; (void)y; (void)width; (void)height; }
void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a) { (void)r; (void)g; (void)b; (void)a; }
void glClear(GLbitfield mask) { (void)mask; }
void glEnable(GLenum cap) { (void)cap; }
void glDisable(GLenum cap) { (void)cap; }
void glBlendFunc(GLenum sfactor, GLenum dfactor) { (void)sfactor; (void)dfactor; }
void glBlendFuncSeparate(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha) { (void)srcRGB; (void)dstRGB; (void)srcAlpha; (void)dstAlpha; }
void glUseProgram(GLuint program) { (void)program; }
void glDeleteProgram(GLuint program) { (void)program; }
void glDeleteShader(GLuint shader) { (void)shader; }
void glDetachShader(GLuint program, GLuint shader) { (void)program; (void)shader; }
GLuint glCreateProgram(void) { return 1; }
GLuint glCreateShader(GLenum type) { (void)type; return 1; }
void glShaderSource(GLuint shader, GLsizei count, const GLchar *const *string, const GLint *length) { (void)shader; (void)count; (void)string; (void)length; }
void glCompileShader(GLuint shader) { (void)shader; }
void glGetShaderiv(GLuint shader, GLenum pname, GLint *params) { (void)shader; (void)pname; if (params != NULL) *params = 1; }
void glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog) { (void)shader; (void)bufSize; if (length != NULL) *length = 0; if (infoLog != NULL) infoLog[0] = 0; }
void glAttachShader(GLuint program, GLuint shader) { (void)program; (void)shader; }
void glLinkProgram(GLuint program) { (void)program; }
void glGetProgramiv(GLuint program, GLenum pname, GLint *params) { (void)program; (void)pname; if (params != NULL) *params = 1; }
void glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog) { (void)program; (void)bufSize; if (length != NULL) *length = 0; if (infoLog != NULL) infoLog[0] = 0; }
GLint glGetUniformLocation(GLuint program, const GLchar *name) { (void)program; (void)name; return 0; }
GLint glGetAttribLocation(GLuint program, const GLchar *name) { (void)program; (void)name; return 0; }
void glUniform1i(GLint location, GLint v0) { (void)location; (void)v0; }
void glUniform1f(GLint location, GLfloat v0) { (void)location; (void)v0; }
void glUniform4f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3) { (void)location; (void)v0; (void)v1; (void)v2; (void)v3; }
void glUniformMatrix3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glUniformMatrix4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glGenBuffers(GLsizei n, GLuint *buffers) { for (GLsizei i = 0; buffers != NULL && i < n; i++) buffers[i] = (GLuint)(i + 1); }
void glBindBuffer(GLenum target, GLuint buffer) { (void)target; (void)buffer; }
void glBufferData(GLenum target, GLsizeiptr size, const void *data, GLenum usage) { (void)target; (void)size; (void)data; (void)usage; }
void glBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, const void *data) { (void)target; (void)offset; (void)size; (void)data; }
void glDeleteBuffers(GLsizei n, const GLuint *buffers) { (void)n; (void)buffers; }
void glGenTextures(GLsizei n, GLuint *textures) { for (GLsizei i = 0; textures != NULL && i < n; i++) textures[i] = (GLuint)(i + 1); }
void glBindTexture(GLenum target, GLuint texture) { (void)target; (void)texture; }
void glTexParameteri(GLenum target, GLenum pname, GLint param) { (void)target; (void)pname; (void)param; }
void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels) { (void)target; (void)level; (void)internalformat; (void)width; (void)height; (void)border; (void)format; (void)type; (void)pixels; }
void glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const void *pixels) { (void)target; (void)level; (void)xoffset; (void)yoffset; (void)width; (void)height; (void)format; (void)type; (void)pixels; }
void glDeleteTextures(GLsizei n, const GLuint *textures) { (void)n; (void)textures; }
void glActiveTexture(GLenum texture) { (void)texture; }
void glPixelStorei(GLenum pname, GLint param) { (void)pname; (void)param; }
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels) { (void)x; (void)y; (void)width; (void)height; (void)format; (void)type; (void)pixels; }
void glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer) { (void)index; (void)size; (void)type; (void)normalized; (void)stride; (void)pointer; }
void glEnableVertexAttribArray(GLuint index) { (void)index; }
void glDisableVertexAttribArray(GLuint index) { (void)index; }
void glDrawArrays(GLenum mode, GLint first, GLsizei count) { (void)mode; (void)first; (void)count; }
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices) { (void)mode; (void)count; (void)type; (void)indices; }
void glGenFramebuffers(GLsizei n, GLuint *ids) { for (GLsizei i = 0; ids != NULL && i < n; i++) ids[i] = (GLuint)(i + 1); }
void glDeleteFramebuffers(GLsizei n, const GLuint *framebuffers) { (void)n; (void)framebuffers; }
void glBindFramebuffer(GLenum target, GLuint framebuffer) { (void)target; (void)framebuffer; }
void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) { (void)target; (void)attachment; (void)textarget; (void)texture; (void)level; }
GLenum glCheckFramebufferStatus(GLenum target) { (void)target; return GL_FRAMEBUFFER_COMPLETE; }
void glGenRenderbuffers(GLsizei n, GLuint *renderbuffers) { for (GLsizei i = 0; renderbuffers != NULL && i < n; i++) renderbuffers[i] = (GLuint)(i + 1); }
void glDeleteRenderbuffers(GLsizei n, const GLuint *renderbuffers) { (void)n; (void)renderbuffers; }
void glBindRenderbuffer(GLenum target, GLuint renderbuffer) { (void)target; (void)renderbuffer; }
void glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei width, GLsizei height) { (void)target; (void)internalformat; (void)width; (void)height; }
void glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer) { (void)target; (void)attachment; (void)renderbuffertarget; (void)renderbuffer; }
void glGetInteger64v(GLenum pname, GLint64 *data) { (void)pname; if (data != NULL) *data = 0; }
void glFlush(void) {}
void glFinish(void) {}
""",
  )?

  fs.write(
    p"laputa-gbm.c",
    """#include <stdint.h>
#include <stdlib.h>

struct gbm_device { int fd; };
struct gbm_bo { uint32_t width, height, stride, format; };
struct gbm_surface { uint32_t width, height, format, flags; };

struct gbm_device *gbm_create_device(int fd)
{
    struct gbm_device *dev = calloc(1, sizeof(*dev));
    if (dev != NULL)
        dev->fd = fd;
    return dev;
}

void gbm_device_destroy(struct gbm_device *gbm)
{
    free(gbm);
}

int gbm_device_get_fd(struct gbm_device *gbm)
{
    return gbm == NULL ? -1 : gbm->fd;
}

const char *gbm_device_get_backend_name(struct gbm_device *gbm)
{
    (void)gbm;
    return "laputa";
}

int gbm_device_is_format_supported(struct gbm_device *gbm, uint32_t format, uint32_t usage)
{
    (void)gbm;
    (void)format;
    (void)usage;
    return 1;
}

struct gbm_surface *gbm_surface_create(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, uint32_t flags)
{
    (void)gbm;
    struct gbm_surface *surface = calloc(1, sizeof(*surface));
    if (surface != NULL) {
        surface->width = width;
        surface->height = height;
        surface->format = format;
        surface->flags = flags;
    }
    return surface;
}

void gbm_surface_destroy(struct gbm_surface *surface)
{
    free(surface);
}

struct gbm_bo *gbm_surface_lock_front_buffer(struct gbm_surface *surface)
{
    struct gbm_bo *bo = calloc(1, sizeof(*bo));
    if (bo != NULL && surface != NULL) {
        bo->width = surface->width;
        bo->height = surface->height;
        bo->format = surface->format;
        bo->stride = surface->width * 4;
    }
    return bo;
}

void gbm_surface_release_buffer(struct gbm_surface *surface, struct gbm_bo *bo)
{
    (void)surface;
    free(bo);
}

struct gbm_bo *gbm_bo_create(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, uint32_t flags)
{
    (void)gbm;
    (void)flags;
    struct gbm_bo *bo = calloc(1, sizeof(*bo));
    if (bo != NULL) {
        bo->width = width;
        bo->height = height;
        bo->format = format;
        bo->stride = width * 4;
    }
    return bo;
}

struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, const uint64_t *modifiers, const unsigned int count)
{
    (void)modifiers;
    (void)count;
    return gbm_bo_create(gbm, width, height, format, 0);
}

void gbm_bo_destroy(struct gbm_bo *bo)
{
    free(bo);
}

uint32_t gbm_bo_get_width(struct gbm_bo *bo) { return bo == NULL ? 0 : bo->width; }
uint32_t gbm_bo_get_height(struct gbm_bo *bo) { return bo == NULL ? 0 : bo->height; }
uint32_t gbm_bo_get_stride(struct gbm_bo *bo) { return bo == NULL ? 0 : bo->stride; }
uint32_t gbm_bo_get_format(struct gbm_bo *bo) { return bo == NULL ? 0 : bo->format; }
uint64_t gbm_bo_get_modifier(struct gbm_bo *bo) { (void)bo; return 0; }
void *gbm_bo_get_user_data(struct gbm_bo *bo) { (void)bo; return NULL; }
void gbm_bo_set_user_data(struct gbm_bo *bo, void *data, void (*destroy_user_data)(struct gbm_bo *, void *)) { (void)bo; (void)data; (void)destroy_user_data; }
int gbm_bo_get_fd(struct gbm_bo *bo) { (void)bo; return -1; }
int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane) { (void)bo; (void)plane; return -1; }
uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane) { (void)plane; return gbm_bo_get_stride(bo); }
uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane) { (void)bo; (void)plane; return 0; }
int gbm_bo_get_plane_count(struct gbm_bo *bo) { (void)bo; return 1; }
""",
  )?
}

proc install_headers(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/include/EGL")?
  fs.mkdir(fp"${dest}/usr/include/GLES2")?
  fs.mkdir(fp"${dest}/usr/include/KHR")?

  fs.write(
    fp"${dest}/usr/include/KHR/khrplatform.h",
    """#ifndef __khrplatform_h_
#define __khrplatform_h_
typedef signed char khronos_int8_t;
typedef unsigned char khronos_uint8_t;
typedef signed short int khronos_int16_t;
typedef unsigned short int khronos_uint16_t;
typedef signed int khronos_int32_t;
typedef unsigned int khronos_uint32_t;
typedef signed long long int khronos_int64_t;
typedef unsigned long long int khronos_uint64_t;
typedef signed long int khronos_intptr_t;
typedef unsigned long int khronos_uintptr_t;
typedef signed long int khronos_ssize_t;
typedef unsigned long int khronos_usize_t;
typedef float khronos_float_t;
#define KHRONOS_APICALL extern
#define KHRONOS_APIENTRY
#define KHRONOS_APIATTRIBUTES
#endif
""",
  )?

  fs.write(
    fp"${dest}/usr/include/EGL/egl.h",
    """#ifndef __egl_h_
#define __egl_h_
#include <KHR/khrplatform.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLSurface;
typedef void *EGLContext;
typedef void *EGLClientBuffer;
typedef void *EGLNativeDisplayType;
typedef void *EGLNativeWindowType;
typedef void *EGLImage;
typedef void *EGLImageKHR;
typedef void *EGLSyncKHR;
typedef void *EGLDeviceEXT;
typedef void *EGLLabelKHR;
typedef khronos_intptr_t EGLAttrib;
typedef int EGLint;
typedef unsigned int EGLBoolean;
typedef unsigned int EGLenum;
#define EGL_FALSE 0
#define EGL_TRUE 1
#define EGL_DEFAULT_DISPLAY ((EGLNativeDisplayType)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_NO_IMAGE_KHR ((EGLImageKHR)0)
#define EGL_NO_SYNC_KHR ((EGLSyncKHR)0)
#define EGL_NO_DEVICE_EXT ((EGLDeviceEXT)0)
#define EGL_NO_CONFIG_KHR ((EGLConfig)0)
#define EGL_SUCCESS 0x3000
#define EGL_NOT_INITIALIZED 0x3001
#define EGL_BAD_ACCESS 0x3002
#define EGL_BAD_ALLOC 0x3003
#define EGL_BAD_ATTRIBUTE 0x3004
#define EGL_BAD_CONFIG 0x3005
#define EGL_BAD_CONTEXT 0x3006
#define EGL_BAD_CURRENT_SURFACE 0x3007
#define EGL_BAD_DISPLAY 0x3008
#define EGL_BAD_MATCH 0x3009
#define EGL_BAD_NATIVE_PIXMAP 0x300A
#define EGL_BAD_NATIVE_WINDOW 0x300B
#define EGL_BAD_PARAMETER 0x300C
#define EGL_BAD_SURFACE 0x300D
#define EGL_CONTEXT_LOST 0x300E
#define EGL_OPENGL_ES_API 0x30A0
#define EGL_OPENGL_ES2_BIT 0x0004
#define EGL_WINDOW_BIT 0x0004
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_SURFACE_TYPE 0x3033
#define EGL_RED_SIZE 0x3024
#define EGL_GREEN_SIZE 0x3023
#define EGL_BLUE_SIZE 0x3022
#define EGL_ALPHA_SIZE 0x3021
#define EGL_DEPTH_SIZE 0x3025
#define EGL_STENCIL_SIZE 0x3026
#define EGL_NONE 0x3038
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_CONTEXT_CLIENT_TYPE 0x3097
#define EGL_CONTEXT_PRIORITY_LEVEL_IMG 0x3100
#define EGL_CONTEXT_PRIORITY_HIGH_IMG 0x3101
#define EGL_CONTEXT_PRIORITY_MEDIUM_IMG 0x3102
#define EGL_VENDOR 0x3053
#define EGL_VERSION 0x3054
#define EGL_EXTENSIONS 0x3055
#define EGL_HEIGHT 0x3056
#define EGL_WIDTH 0x3057
#define EGL_DRAW 0x3059
#define EGL_READ 0x305A
#define EGL_PLATFORM_GBM_KHR 0x31D7
#define EGL_PLATFORM_DEVICE_EXT 0x313F
#define EGL_DEVICE_EXT 0x322C
#define EGL_BAD_DEVICE_EXT 0x322B
#define EGL_DRM_DEVICE_FILE_EXT 0x3233
#define EGL_DRM_RENDER_NODE_FILE_EXT 0x3377
#define EGL_LINUX_DMA_BUF_EXT 0x3270
#define EGL_LINUX_DRM_FOURCC_EXT 0x3271
#define EGL_DMA_BUF_PLANE0_FD_EXT 0x3272
#define EGL_DMA_BUF_PLANE0_OFFSET_EXT 0x3273
#define EGL_DMA_BUF_PLANE0_PITCH_EXT 0x3274
#define EGL_DMA_BUF_PLANE1_FD_EXT 0x3275
#define EGL_DMA_BUF_PLANE1_OFFSET_EXT 0x3276
#define EGL_DMA_BUF_PLANE1_PITCH_EXT 0x3277
#define EGL_DMA_BUF_PLANE2_FD_EXT 0x3278
#define EGL_DMA_BUF_PLANE2_OFFSET_EXT 0x3279
#define EGL_DMA_BUF_PLANE2_PITCH_EXT 0x327A
#define EGL_DMA_BUF_PLANE3_FD_EXT 0x3440
#define EGL_DMA_BUF_PLANE3_OFFSET_EXT 0x3441
#define EGL_DMA_BUF_PLANE3_PITCH_EXT 0x3442
#define EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT 0x3443
#define EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT 0x3444
#define EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT 0x3445
#define EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT 0x3446
#define EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT 0x3447
#define EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT 0x3448
#define EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT 0x3449
#define EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT 0x344A
#define EGL_IMAGE_PRESERVED_KHR 0x30D2
#define EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_KHR 0x31BD
#define EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_EXT 0x3138
#define EGL_LOSE_CONTEXT_ON_RESET_KHR 0x31BF
#define EGL_LOSE_CONTEXT_ON_RESET_EXT 0x31BF
#define EGL_DEBUG_MSG_CRITICAL_KHR 0x33B9
#define EGL_DEBUG_MSG_ERROR_KHR 0x33BA
#define EGL_DEBUG_MSG_WARN_KHR 0x33BB
#define EGL_DEBUG_MSG_INFO_KHR 0x33BC
#define EGL_TRACK_REFERENCES_KHR 0x3352
#define EGL_DRIVER_NAME_EXT 0x335E
#define EGL_SYNC_NATIVE_FENCE_ANDROID 0x3144
#define EGL_SYNC_NATIVE_FENCE_FD_ANDROID 0x3145
#define EGL_NO_NATIVE_FENCE_FD_ANDROID -1
typedef EGLDisplay (*PFNEGLGETPLATFORMDISPLAYEXTPROC)(EGLenum platform, void *native_display, const EGLint *attrib_list);
typedef EGLImageKHR (*PFNEGLCREATEIMAGEKHRPROC)(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buffer, const EGLint *attrib_list);
typedef EGLBoolean (*PFNEGLDESTROYIMAGEKHRPROC)(EGLDisplay dpy, EGLImageKHR image);
typedef EGLBoolean (*PFNEGLQUERYDMABUFFORMATSEXTPROC)(EGLDisplay dpy, EGLint max_formats, EGLint *formats, EGLint *num_formats);
typedef EGLBoolean (*PFNEGLQUERYDMABUFMODIFIERSEXTPROC)(EGLDisplay dpy, EGLint format, EGLint max_modifiers, uint64_t *modifiers, EGLBoolean *external_only, EGLint *num_modifiers);
typedef void (*EGLDEBUGPROCKHR)(EGLenum error, const char *command, EGLint message_type, EGLLabelKHR thread_label, EGLLabelKHR object_label, const char *message);
typedef EGLint (*PFNEGLDEBUGMESSAGECONTROLKHRPROC)(EGLDEBUGPROCKHR callback, const EGLAttrib *attrib_list);
typedef EGLBoolean (*PFNEGLQUERYDISPLAYATTRIBEXTPROC)(EGLDisplay dpy, EGLint attribute, EGLAttrib *value);
typedef const char *(*PFNEGLQUERYDEVICESTRINGEXTPROC)(EGLDeviceEXT device, EGLint name);
typedef EGLBoolean (*PFNEGLQUERYDEVICESEXTPROC)(EGLint max_devices, EGLDeviceEXT *devices, EGLint *num_devices);
typedef EGLSyncKHR (*PFNEGLCREATESYNCKHRPROC)(EGLDisplay dpy, EGLenum type, const EGLint *attrib_list);
typedef EGLBoolean (*PFNEGLDESTROYSYNCKHRPROC)(EGLDisplay dpy, EGLSyncKHR sync);
typedef int (*PFNEGLDUPNATIVEFENCEFDANDROIDPROC)(EGLDisplay dpy, EGLSyncKHR sync);
typedef EGLBoolean (*PFNEGLWAITSYNCKHRPROC)(EGLDisplay dpy, EGLSyncKHR sync, EGLint flags);
EGLDisplay eglGetDisplay(EGLNativeDisplayType display_id);
EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *native_display, const EGLint *attrib_list);
EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor);
EGLBoolean eglTerminate(EGLDisplay dpy);
EGLBoolean eglBindAPI(EGLenum api);
EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attrib_list, EGLConfig *configs, EGLint config_size, EGLint *num_config);
EGLBoolean eglGetConfigs(EGLDisplay dpy, EGLConfig *configs, EGLint config_size, EGLint *num_config);
EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config, EGLContext share_context, const EGLint *attrib_list);
EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx);
EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint *attrib_list);
EGLSurface eglCreatePlatformWindowSurface(EGLDisplay dpy, EGLConfig config, void *native_window, const EGLint *attrib_list);
EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface);
EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx);
EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface);
EGLBoolean eglQueryContext(EGLDisplay dpy, EGLContext ctx, EGLint attribute, EGLint *value);
EGLBoolean eglQuerySurface(EGLDisplay dpy, EGLSurface surface, EGLint attribute, EGLint *value);
EGLint eglGetError(void);
EGLDisplay eglGetCurrentDisplay(void);
EGLContext eglGetCurrentContext(void);
EGLSurface eglGetCurrentSurface(EGLint readdraw);
const char *eglQueryString(EGLDisplay dpy, EGLint name);
void *eglGetProcAddress(const char *procname);
EGLBoolean eglSwapInterval(EGLDisplay dpy, EGLint interval);
EGLBoolean eglReleaseThread(void);
#ifdef __cplusplus
}
#endif
#endif
""",
  )?

  fs.write(
    fp"${dest}/usr/include/EGL/eglext.h",
    """#ifndef __eglext_h_
#define __eglext_h_
#define EGL_EGLEXT_VERSION 20210604
#include <EGL/egl.h>
#endif
""",
  )?

  fs.write(
    fp"${dest}/usr/include/EGL/eglplatform.h",
    """#ifndef __eglplatform_h_
#define __eglplatform_h_
#include <KHR/khrplatform.h>
#endif
""",
  )?

  fs.write(
    fp"${dest}/usr/include/GLES2/gl2.h",
    """#ifndef __gl2_h_
#define __gl2_h_
#include <KHR/khrplatform.h>
#ifdef __cplusplus
extern "C" {
#endif
#ifndef GL_APICALL
#define GL_APICALL KHRONOS_APICALL
#endif
#ifndef GL_APIENTRY
#define GL_APIENTRY KHRONOS_APIENTRY
#endif
#ifndef GL_APIENTRYP
#define GL_APIENTRYP GL_APIENTRY *
#endif
typedef unsigned int GLenum;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef void GLvoid;
typedef signed char GLbyte;
typedef short GLshort;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef float GLfloat;
typedef float GLclampf;
typedef khronos_ssize_t GLsizeiptr;
typedef khronos_intptr_t GLintptr;
typedef khronos_int64_t GLint64;
typedef khronos_uint64_t GLuint64;
typedef char GLchar;
typedef void *GLeglImageOES;
typedef void (*GLDEBUGPROCKHR)(GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, const GLchar *message, const void *userParam);
#define GL_FALSE 0
#define GL_TRUE 1
#define GL_NO_ERROR 0
#define GL_VENDOR 0x1F00
#define GL_RENDERER 0x1F01
#define GL_VERSION 0x1F02
#define GL_EXTENSIONS 0x1F03
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_TEXTURE_2D 0x0DE1
#define GL_TEXTURE0 0x84C0
#define GL_FLOAT 0x1406
#define GL_TRIANGLES 0x0004
#define GL_UNSIGNED_SHORT 0x1403
#define GL_UNSIGNED_SHORT_4_4_4_4 0x8033
#define GL_UNSIGNED_SHORT_5_5_5_1 0x8034
#define GL_UNSIGNED_SHORT_5_6_5 0x8363
#define GL_ARRAY_BUFFER 0x8892
#define GL_STATIC_DRAW 0x88E4
#define GL_STREAM_DRAW 0x88E0
#define GL_VERTEX_SHADER 0x8B31
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_BLEND 0x0BE2
#define GL_SCISSOR_TEST 0x0C11
#define GL_ONE 1
#define GL_ONE_MINUS_SRC_ALPHA 0x0303
#define GL_RGBA 0x1908
#define GL_RGBA16_EXT 0x805B
#define GL_RGB 0x1907
#define GL_ALPHA_BITS 0x0D55
#define GL_BGRA_EXT 0x80E1
#define GL_UNSIGNED_BYTE 0x1401
#define GL_UNSIGNED_INT_2_10_10_10_REV_EXT 0x8368
#define GL_HALF_FLOAT_OES 0x8D61
#define GL_FRAGMENT_PRECISION_HIGH 0x8DF2
#define GL_IMPLEMENTATION_COLOR_READ_TYPE 0x8B9A
#define GL_IMPLEMENTATION_COLOR_READ_FORMAT 0x8B9B
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_LINEAR 0x2601
#define GL_NEAREST 0x2600
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_TEXTURE_EXTERNAL_OES 0x8D65
#define GL_FRAMEBUFFER 0x8D40
#define GL_RENDERBUFFER 0x8D41
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_PACK_ALIGNMENT 0x0D05
#define GL_PACK_ROW_LENGTH 0x0D02
#define GL_UNPACK_ROW_LENGTH_EXT 0x0CF2
#define GL_UNPACK_SKIP_PIXELS_EXT 0x0CF4
#define GL_UNPACK_SKIP_ROWS_EXT 0x0CF3
#define GL_TIMESTAMP_EXT 0x8E28
#define GL_GPU_DISJOINT_EXT 0x8FBB
#define GL_QUERY_RESULT_EXT 0x8866
#define GL_QUERY_RESULT_AVAILABLE_EXT 0x8867
#define GL_GUILTY_CONTEXT_RESET_KHR 0x8253
#define GL_INNOCENT_CONTEXT_RESET_KHR 0x8254
#define GL_UNKNOWN_CONTEXT_RESET_KHR 0x8255
#define GL_RESET_NOTIFICATION_STRATEGY_KHR 0x8256
#define GL_LOSE_CONTEXT_ON_RESET_KHR 0x8252
#define GL_NO_RESET_NOTIFICATION_KHR 0x8261
#define GL_CONTEXT_LOST_KHR 0x0507
#define GL_DEBUG_OUTPUT_KHR 0x92E0
#define GL_DEBUG_OUTPUT_SYNCHRONOUS_KHR 0x8242
#define GL_DEBUG_SOURCE_APPLICATION_KHR 0x824A
#define GL_DEBUG_TYPE_ERROR_KHR 0x824C
#define GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR_KHR 0x824D
#define GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR_KHR 0x824E
#define GL_DEBUG_TYPE_PORTABILITY_KHR 0x824F
#define GL_DEBUG_TYPE_PERFORMANCE_KHR 0x8250
#define GL_DEBUG_TYPE_OTHER_KHR 0x8251
#define GL_DEBUG_TYPE_MARKER_KHR 0x8268
#define GL_DEBUG_TYPE_PUSH_GROUP_KHR 0x8269
#define GL_DEBUG_TYPE_POP_GROUP_KHR 0x826A
#define GL_DONT_CARE 0x1100
typedef void (GL_APIENTRYP PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)(GLenum target, GLeglImageOES image);
typedef void (GL_APIENTRYP PFNGLEGLIMAGETARGETRENDERBUFFERSTORAGEOESPROC)(GLenum target, GLeglImageOES image);
typedef void (GL_APIENTRYP PFNGLDEBUGMESSAGECALLBACKKHRPROC)(GLDEBUGPROCKHR callback, const void *userParam);
typedef void (GL_APIENTRYP PFNGLDEBUGMESSAGECONTROLKHRPROC)(GLenum source, GLenum type, GLenum severity, GLsizei count, const GLuint *ids, GLboolean enabled);
typedef void (GL_APIENTRYP PFNGLPOPDEBUGGROUPKHRPROC)(void);
typedef void (GL_APIENTRYP PFNGLPUSHDEBUGGROUPKHRPROC)(GLenum source, GLuint id, GLsizei length, const GLchar *message);
typedef GLenum (GL_APIENTRYP PFNGLGETGRAPHICSRESETSTATUSKHRPROC)(void);
typedef void (GL_APIENTRYP PFNGLGENQUERIESEXTPROC)(GLsizei n, GLuint *ids);
typedef void (GL_APIENTRYP PFNGLDELETEQUERIESEXTPROC)(GLsizei n, const GLuint *ids);
typedef void (GL_APIENTRYP PFNGLQUERYCOUNTEREXTPROC)(GLuint id, GLenum target);
typedef void (GL_APIENTRYP PFNGLGETQUERYOBJECTIVEXTPROC)(GLuint id, GLenum pname, GLint *params);
typedef void (GL_APIENTRYP PFNGLGETQUERYOBJECTUI64VEXTPROC)(GLuint id, GLenum pname, GLuint64 *params);
typedef void (GL_APIENTRYP PFNGLGETINTEGER64VEXTPROC)(GLenum pname, GLint64 *data);
const GLubyte *glGetString(GLenum name);
GLenum glGetError(void);
void glGetIntegerv(GLenum pname, GLint *data);
void glGetFloatv(GLenum pname, GLfloat *data);
void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
void glScissor(GLint x, GLint y, GLsizei width, GLsizei height);
void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
void glClear(GLbitfield mask);
void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glBlendFunc(GLenum sfactor, GLenum dfactor);
void glBlendFuncSeparate(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha);
void glUseProgram(GLuint program);
void glDeleteProgram(GLuint program);
void glDeleteShader(GLuint shader);
void glDetachShader(GLuint program, GLuint shader);
GLuint glCreateProgram(void);
GLuint glCreateShader(GLenum type);
void glShaderSource(GLuint shader, GLsizei count, const GLchar *const *string, const GLint *length);
void glCompileShader(GLuint shader);
void glGetShaderiv(GLuint shader, GLenum pname, GLint *params);
void glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
void glAttachShader(GLuint program, GLuint shader);
void glLinkProgram(GLuint program);
void glGetProgramiv(GLuint program, GLenum pname, GLint *params);
void glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
GLint glGetUniformLocation(GLuint program, const GLchar *name);
GLint glGetAttribLocation(GLuint program, const GLchar *name);
void glUniform1i(GLint location, GLint v0);
void glUniform1f(GLint location, GLfloat v0);
void glUniform4f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3);
void glUniformMatrix3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniformMatrix4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glGenBuffers(GLsizei n, GLuint *buffers);
void glBindBuffer(GLenum target, GLuint buffer);
void glBufferData(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
void glBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, const void *data);
void glDeleteBuffers(GLsizei n, const GLuint *buffers);
void glGenTextures(GLsizei n, GLuint *textures);
void glBindTexture(GLenum target, GLuint texture);
void glTexParameteri(GLenum target, GLenum pname, GLint param);
void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
void glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const void *pixels);
void glDeleteTextures(GLsizei n, const GLuint *textures);
void glActiveTexture(GLenum texture);
void glPixelStorei(GLenum pname, GLint param);
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels);
void glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer);
void glEnableVertexAttribArray(GLuint index);
void glDisableVertexAttribArray(GLuint index);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices);
void glGenFramebuffers(GLsizei n, GLuint *ids);
void glDeleteFramebuffers(GLsizei n, const GLuint *framebuffers);
void glBindFramebuffer(GLenum target, GLuint framebuffer);
void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
GLenum glCheckFramebufferStatus(GLenum target);
void glGenRenderbuffers(GLsizei n, GLuint *renderbuffers);
void glDeleteRenderbuffers(GLsizei n, const GLuint *renderbuffers);
void glBindRenderbuffer(GLenum target, GLuint renderbuffer);
void glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei width, GLsizei height);
void glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer);
void glGetInteger64v(GLenum pname, GLint64 *data);
void glFlush(void);
void glFinish(void);
#ifdef __cplusplus
}
#endif
#endif
""",
  )?

  fs.write(
    fp"${dest}/usr/include/GLES2/gl2ext.h",
    """#ifndef __gl2ext_h_
#define __gl2ext_h_
#include <GLES2/gl2.h>
#endif
""",
  )?

  fs.write(
    fp"${dest}/usr/include/GLES2/gl2platform.h",
    """#ifndef __gl2platform_h_
#define __gl2platform_h_
#include <KHR/khrplatform.h>
#endif
""",
  )?

  fs.write(
    fp"${dest}/usr/include/gbm.h",
    """#ifndef LAPUTA_GBM_H
#define LAPUTA_GBM_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
struct gbm_device;
struct gbm_bo;
struct gbm_surface;
#define GBM_BO_USE_SCANOUT (1 << 0)
#define GBM_BO_USE_RENDERING (1 << 2)
#define GBM_BO_USE_LINEAR (1 << 4)
#define GBM_FORMAT_XRGB8888 0x34325258
#define GBM_FORMAT_ARGB8888 0x34325241
struct gbm_device *gbm_create_device(int fd);
void gbm_device_destroy(struct gbm_device *gbm);
int gbm_device_get_fd(struct gbm_device *gbm);
const char *gbm_device_get_backend_name(struct gbm_device *gbm);
int gbm_device_is_format_supported(struct gbm_device *gbm, uint32_t format, uint32_t usage);
struct gbm_surface *gbm_surface_create(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, uint32_t flags);
void gbm_surface_destroy(struct gbm_surface *surface);
struct gbm_bo *gbm_surface_lock_front_buffer(struct gbm_surface *surface);
void gbm_surface_release_buffer(struct gbm_surface *surface, struct gbm_bo *bo);
struct gbm_bo *gbm_bo_create(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, uint32_t flags);
struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, const uint64_t *modifiers, const unsigned int count);
void gbm_bo_destroy(struct gbm_bo *bo);
uint32_t gbm_bo_get_width(struct gbm_bo *bo);
uint32_t gbm_bo_get_height(struct gbm_bo *bo);
uint32_t gbm_bo_get_stride(struct gbm_bo *bo);
uint32_t gbm_bo_get_format(struct gbm_bo *bo);
uint64_t gbm_bo_get_modifier(struct gbm_bo *bo);
void *gbm_bo_get_user_data(struct gbm_bo *bo);
void gbm_bo_set_user_data(struct gbm_bo *bo, void *data, void (*destroy_user_data)(struct gbm_bo *, void *));
int gbm_bo_get_fd(struct gbm_bo *bo);
int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane);
uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane);
uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane);
int gbm_bo_get_plane_count(struct gbm_bo *bo);
#ifdef __cplusplus
}
#endif
#endif
""",
  )?
}

proc install_pkg_config(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/lib/pkgconfig")?

  for pc in [
    {name: "egl", desc: "Laputa minimal EGL", libs: "-lEGL"},
    {name: "glesv2", desc: "Laputa minimal GLESv2", libs: "-lGLESv2"},
    {name: "gbm", desc: "Laputa minimal GBM", libs: "-lgbm"},
  ] {
    let pc_name: Str = pc.get("name")?
    let desc: Str = pc.get("desc")?
    let libs: Str = pc.get("libs")?

    fs.write(
      fp"${dest}/usr/lib/pkgconfig/${pc_name}.pc",
      f"""prefix=/usr
exec_prefix=\${{prefix}}
libdir=\${{exec_prefix}}/lib
includedir=\${{prefix}}/include

Name: ${pc_name}
Description: ${desc}
Version: ${ver}
Libs: -L\${{libdir}} ${libs}
Cflags: -I\${{includedir}}
""",
    )?
  }
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"
  let cflags = ["-std=c99", "-Wall", "-Wextra"]
  write_sources()?
  let egl = make.c_shared_library({
    cc,
    triple,
    cflags,
    defs: [],
    includes: [],
    root: p".",
    sources: [p"laputa-egl.c"],
    out_dir: p"obj/egl",
    out: p"obj/libEGL.so.1.0.0",
    soname: "libEGL.so.1",
    ldflags: [],
    deps: [],
  })
  let gles = make.c_shared_library({
    cc,
    triple,
    cflags,
    defs: [],
    includes: [],
    root: p".",
    sources: [p"laputa-gles2.c"],
    out_dir: p"obj/gles2",
    out: p"obj/libGLESv2.so.2.0.0",
    soname: "libGLESv2.so.2",
    ldflags: [],
    deps: [],
  })
  let gbm = make.c_shared_library({
    cc,
    triple,
    cflags,
    defs: [],
    includes: [],
    root: p".",
    sources: [p"laputa-gbm.c"],
    out_dir: p"obj/gbm",
    out: p"obj/libgbm.so.1.0.0",
    soname: "libgbm.so.1",
    ldflags: [],
    deps: [],
  })

  make.run_tasks(egl.tasks.extend(gles.tasks).extend(gbm.tasks), make.jobs()?)?

  fs.install(egl.output, fp"${dest}/usr/lib/libEGL.so.1.0.0", 0o755, parents: true, overwrite: true)?
  fs.install(gles.output, fp"${dest}/usr/lib/libGLESv2.so.2.0.0", 0o755, parents: true, overwrite: true)?
  fs.install(gbm.output, fp"${dest}/usr/lib/libgbm.so.1.0.0", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"libEGL.so.1.0.0", fp"${dest}/usr/lib/libEGL.so.1")?
  fs.symlink(p"libEGL.so.1.0.0", fp"${dest}/usr/lib/libEGL.so")?
  fs.symlink(p"libGLESv2.so.2.0.0", fp"${dest}/usr/lib/libGLESv2.so.2")?
  fs.symlink(p"libGLESv2.so.2.0.0", fp"${dest}/usr/lib/libGLESv2.so")?
  fs.symlink(p"libgbm.so.1.0.0", fp"${dest}/usr/lib/libgbm.so.1")?
  fs.symlink(p"libgbm.so.1.0.0", fp"${dest}/usr/lib/libgbm.so")?
  install_headers(dest)?
  install_pkg_config(dest)?
}
