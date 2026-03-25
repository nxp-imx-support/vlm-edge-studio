/*
 * SPDX-License-Identifier: BSD-3-Clause
 * Copyright 2025-2026 NXP
 *
 * Example Qt Application for GStreamer pipelines rendered through OpenGL ES
 *
 */

#include <QtQml/qqmlextensionplugin.h>
#include <gst/gst.h>

#include <QColorSpace>
#include <QDebug>
#include <QDir>
#include <QGuiApplication>
#include <QLoggingCategory>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQmlApplicationEngine>
#include <QQuickView>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QSurfaceFormat>
#include <QRegularExpression>

#include "gstqmlglsink.h"
#include "gsttestglsink.h"
#include "submitprompt.h"

// Enable Qt logging categories for debugging
Q_LOGGING_CATEGORY(lcMain, "main")
Q_LOGGING_CATEGORY(lcOpenGL, "opengl")
Q_LOGGING_CATEGORY(lcGStreamer, "gstreamer")

void setupGStreamerEnvironment() {
  qCDebug(lcGStreamer) << "Setting up GStreamer environment...";

  // Set locale for GStreamer compatibility
  qputenv("LC_ALL", "C.UTF-8");
  qputenv("LANG", "C.UTF-8");

  // GStreamer performance optimizations
  qputenv("GST_DEBUG", "0");  // Set to 0 for production, 2+ for debugging

  // Plugin path for embedded systems
  QStringList pluginPaths;
  pluginPaths << "/usr/lib/gstreamer-1.0" << "/usr/local/lib/gstreamer-1.0"
              << "/opt/gstreamer/lib/gstreamer-1.0";

  for (const QString &path : pluginPaths) {
    if (QDir(path).exists()) {
      QString currentPath = qgetenv("GST_PLUGIN_PATH");
      if (!currentPath.isEmpty()) {
        qputenv("GST_PLUGIN_PATH", (currentPath + ":" + path).toUtf8());
      } else {
        qputenv("GST_PLUGIN_PATH", path.toUtf8());
      }
      qCDebug(lcGStreamer) << "Added plugin path:" << path;
    }
  }

  // Video-specific optimizations
  qputenv("GST_GL_WINDOW", "x11");    // Force X11 for better compatibility
  qputenv("GST_GL_API", "gles2");     // Force OpenGL ES 2.0+
  qputenv("GST_GL_PLATFORM", "egl");  // Use EGL platform

  // Memory optimizations
  qputenv("GST_BUFFER_POOL_OPTION_VIDEO_GL_TEXTURE_UPLOAD_META", "1");

  // i.MX specific optimizations (if applicable)
  qputenv("GST_IMX_DISABLE_PHYS_MEM_BLOCKS", "1");

  qCDebug(lcGStreamer) << "GStreamer environment configured";
}

void setupOptimalSurfaceFormat() {
  qCDebug(lcOpenGL) << "Configuring optimal OpenGL surface format...";

  QSurfaceFormat format;

  // Set OpenGL ES version - prefer 3.2 but fallback gracefully
  format.setVersion(3, 1);
  format.setRenderableType(QSurfaceFormat::OpenGLES);

  // Buffer configurations optimized for video
  format.setDepthBufferSize(0);    // No depth buffer needed for video
  format.setStencilBufferSize(0);  // No stencil buffer needed
  format.setSamples(0);            // No multisampling for better performance
  format.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
  format.setSwapInterval(1);  // VSync for smooth video

  // Color space - using modern QColorSpace
  format.setColorSpace(QColorSpace(QColorSpace::SRgb));
  format.setRedBufferSize(8);
  format.setGreenBufferSize(8);
  format.setBlueBufferSize(8);
  format.setAlphaBufferSize(8);

  // Enable debug context in debug builds
#ifdef QT_DEBUG
  format.setOption(QSurfaceFormat::DebugContext);
#endif

  QSurfaceFormat::setDefaultFormat(format);
  qCDebug(lcOpenGL) << "Surface format configured";
}


// Simple global variables
int g_openglMajor = 0;
int g_openglMinor = 0;
bool g_isOpenGLES = false;

void printOpenGLInfo() {
  // Create a temporary context to get OpenGL information
  QOpenGLContext tempContext;
  QOffscreenSurface surface;

  surface.setFormat(QSurfaceFormat::defaultFormat());
  surface.create();

  if (!tempContext.create()) {
    qCWarning(lcOpenGL)
        << "Failed to create OpenGL context for information gathering";
    return;
  }

  if (!tempContext.makeCurrent(&surface)) {
    qCWarning(lcOpenGL) << "Failed to make OpenGL context current";
    return;
  }

  QOpenGLFunctions *gl = tempContext.functions();
  if (!gl) {
    qCWarning(lcOpenGL) << "Failed to get OpenGL functions";
    return;
  }

  // Get version string and parse it
  QString versionString = QString::fromUtf8((const char *)gl->glGetString(GL_VERSION));

  // Simple regex to extract version numbers
  QRegularExpression versionRegex(R"((\d+)\.(\d+))");
  QRegularExpressionMatch match = versionRegex.match(versionString);

  if (match.hasMatch()) {
    g_openglMajor = match.captured(1).toInt();
    g_openglMinor = match.captured(2).toInt();
    g_isOpenGLES = versionString.contains("ES");

    qCInfo(lcOpenGL) << "Detected OpenGL" << (g_isOpenGLES ? "ES" : "")
                     << g_openglMajor << "." << g_openglMinor;
  }

  // Print comprehensive OpenGL information
  qCInfo(lcOpenGL) << "=== OpenGL Information ===";
  qCInfo(lcOpenGL) << "Vendor:" << (const char *)gl->glGetString(GL_VENDOR);
  qCInfo(lcOpenGL) << "Renderer:" << (const char *)gl->glGetString(GL_RENDERER);
  qCInfo(lcOpenGL) << "Version:" << versionString;
  qCInfo(lcOpenGL) << "GLSL Version:" << (const char *)gl->glGetString(GL_SHADING_LANGUAGE_VERSION);

  // Context format information
  QSurfaceFormat format = tempContext.format();
  qCInfo(lcOpenGL) << "Surface Format:";
  qCInfo(lcOpenGL) << "  - OpenGL Version:" << format.majorVersion() << "."
                   << format.minorVersion();
  qCInfo(lcOpenGL) << "  - Profile:"
                   << (format.profile() == QSurfaceFormat::CoreProfile ? "Core"
                       : format.profile() ==
                               QSurfaceFormat::CompatibilityProfile
                           ? "Compatibility"
                           : "No Profile");
  qCInfo(lcOpenGL) << "  - OpenGL ES:"
                   << (tempContext.isOpenGLES() ? "Yes" : "No");
  qCInfo(lcOpenGL) << "  - Color Buffer Size:" << format.redBufferSize()
                   << format.greenBufferSize() << format.blueBufferSize()
                   << format.alphaBufferSize();
  qCInfo(lcOpenGL) << "  - Depth Buffer Size:" << format.depthBufferSize();
  qCInfo(lcOpenGL) << "  - Stencil Buffer Size:" << format.stencilBufferSize();
  qCInfo(lcOpenGL) << "  - Samples:" << format.samples();
  qCInfo(lcOpenGL) << "  - Swap Behavior:"
                   << (format.swapBehavior() == QSurfaceFormat::DoubleBuffer
                           ? "Double"
                           : "Single");
  qCInfo(lcOpenGL) << "  - Swap Interval:" << format.swapInterval();

  // Extension information (limited output)
  QSet<QByteArray> extensions = tempContext.extensions();
  qCInfo(lcOpenGL) << "Extensions count:" << extensions.size();

  // Check for important video-related extensions
  QStringList importantExtensions = {
      "GL_EXT_texture_format_BGRA8888", "GL_OES_EGL_image",
      "GL_OES_EGL_image_external", "GL_OES_vertex_array_object",
      "GL_EXT_unpack_subimage"};

  qCInfo(lcOpenGL) << "Important video extensions:";
  for (const QString &ext : importantExtensions) {
    bool hasExt = extensions.contains(ext.toUtf8());
    qCInfo(lcOpenGL) << "  -" << ext << ":" << (hasExt ? "YES" : "NO");
  }

  qCInfo(lcOpenGL) << "========================";

  tempContext.doneCurrent();
}

// Simple helper functions
bool isOpenGLVersionAtLeast(int major, int minor) {
  return (g_openglMajor > major) || (g_openglMajor == major && g_openglMinor >= minor);
}

int main(int argc, char *argv[]) {
  // Enable high DPI support
  QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
      Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

  // Setup GStreamer environment before QGuiApplication
  setupGStreamerEnvironment();

  // Configure optimal surface format
  setupOptimalSurfaceFormat();

  // Force Qt to use OpenGL
  QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

  QGuiApplication app(argc, argv);

  // Set application properties
  app.setApplicationName("GStreamer Qt6 GL Video Player");
  app.setApplicationVersion("1.0.0");
  app.setOrganizationName("YourOrganization");
  app.setOrganizationDomain("yourorganization.com");

  qCInfo(lcMain) << "=== Application Startup ===";
  qCInfo(lcMain) << "Application:" << app.applicationName();
  qCInfo(lcMain) << "Version:" << app.applicationVersion();
  qCInfo(lcMain) << "Qt Version:" << QT_VERSION_STR;
  qCInfo(lcMain) << "Arguments:" << app.arguments();

  // Print system information
  printOpenGLInfo();

  // Register QML types
  qCInfo(lcMain) << "Registering QML types...";
  qmlRegisterType<GstTestGLSink>("GStreamerApp", 1, 0, "GstTestGLSink");
  qmlRegisterType<SubmitPrompt>("SubmitPrompt", 1, 0, "SubmitPrompt");

  // Create QML engine
  QQmlApplicationEngine engine;

  // Setup QML debugging if needed
#ifdef QT_DEBUG
  QLoggingCategory::setFilterRules("qt.qml.debug=true");
#endif

  // Load QML file
  qCInfo(lcMain) << "Loading QML interface...";
  const QUrl qmlUrl(QStringLiteral("qrc:/main.qml"));

  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreated, &app,
      [qmlUrl](QObject *obj, const QUrl &objUrl) {
        if (!obj && qmlUrl == objUrl) {
          qCCritical(lcMain) << "Failed to load QML file:" << qmlUrl;
          QCoreApplication::exit(-1);
        } else {
          qCInfo(lcMain) << "QML interface loaded successfully";
        }
      },
      Qt::QueuedConnection);

  engine.load(qmlUrl);

  if (engine.rootObjects().isEmpty()) {
    qCCritical(lcMain) << "No root objects found in QML file";
    return -1;
  }

  qCInfo(lcMain) << "Application initialized successfully";
  qCInfo(lcMain) << "==========================";

  // Run the application
  int result = app.exec();

  qCInfo(lcMain) << "Application exiting with code:" << result;
  return result;
}
