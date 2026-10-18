#include "mpvitem.h"
#include "windowstate.h"

#include <QtGui/QGuiApplication>
#include <QtGui/QIcon>
#include <QtCore/QStandardPaths>
#include <QtGui/QOpenGLContext>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkDiskCache>
#include <QtQml/QQmlNetworkAccessManagerFactory>
#include <QtOpenGL/QOpenGLFramebufferObject>
#include <QtQuick/QQuickOpenGLUtils>
#include <QtQuick/QQuickWindow>
#include <clocale>
#include <stdexcept>

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h> // windows.h without the min/max macros
#include <dwmapi.h>
#elif defined(Q_OS_LINUX)
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusReply>
#endif

MpvCore::~MpvCore() {
    if (gl) mpv_render_context_free(gl);
    if (mpv) mpv_terminate_destroy(mpv);
}

namespace {

void *getProcAddress(void *, const char *name) {
    auto *ctx = QOpenGLContext::currentContext();
    return ctx ? reinterpret_cast<void *>(ctx->getProcAddress(QByteArray(name))) : nullptr;
}

class MpvRenderer : public QQuickFramebufferObject::Renderer {
    const MpvItem *item;
    std::shared_ptr<MpvCore> core;

public:
    explicit MpvRenderer(const MpvItem *i) : item(i), core(i->core) {}

    ~MpvRenderer() override {
        // Runs on the render thread with the GL context current.
        std::lock_guard lock(core->glLock);
        if (core->gl) {
            mpv_render_context_free(core->gl);
            core->gl = nullptr;
        }
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override {
        if (!core->gl) {
            std::lock_guard lock(core->glLock);
            mpv_opengl_init_params glInit{getProcAddress, nullptr};
            int advanced = 1;
            mpv_render_param params[]{
                {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
                {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
                {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
                {MPV_RENDER_PARAM_INVALID, nullptr},
            };
            if (mpv_render_context_create(&core->gl, core->mpv, params) < 0)
                throw std::runtime_error("failed to initialize mpv GL context");
            mpv_render_context_set_update_callback(
                core->gl,
                [](void *ctx) { QMetaObject::invokeMethod(static_cast<MpvItem *>(ctx), &QQuickItem::update, Qt::QueuedConnection); },
                const_cast<MpvItem *>(item));
            QMetaObject::invokeMethod(const_cast<MpvItem *>(item), &MpvItem::markReady, Qt::QueuedConnection);
        }
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override {
        QQuickOpenGLUtils::resetOpenGLState();
        // Advanced control also queues renderer work for requests such as the stats overlay.
        mpv_render_context_update(core->gl);
        auto *fbo = framebufferObject();
        mpv_opengl_fbo mpfbo{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flipY = 0;
        mpv_render_param params[]{
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(core->gl, params);
        QQuickOpenGLUtils::resetOpenGLState();
    }
};

} // namespace

MpvItem::MpvItem(QQuickItem *parent) : QQuickFramebufferObject(parent), core(std::make_shared<MpvCore>()) {
    core->mpv = mpv_create();
    if (!core->mpv) throw std::runtime_error("could not create mpv context");
    auto *m = core->mpv;
    mpv_set_option_string(m, "vo", "libmpv");
    mpv_set_option_string(m, "idle", "yes");
    mpv_set_option_string(m, "terminal", "no");
    mpv_set_option_string(m, "input-default-bindings", "no");
    mpv_set_option_string(m, "hwdec", "auto-safe");
    if (mpv_initialize(m) < 0) throw std::runtime_error("could not initialize mpv context");
    // Errors are always collected for endFile; warnings only when debugging.
    mpv_request_log_messages(m, qEnvironmentVariableIsSet("AIKATSU_MPV_LOG") ? "warn" : "error");

    mpv_observe_property(m, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(m, 0, "paused-for-cache", MPV_FORMAT_FLAG);
    mpv_observe_property(m, 0, "idle-active", MPV_FORMAT_FLAG);
    mpv_observe_property(m, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m, 0, "track-list", MPV_FORMAT_STRING); // node props stringify as JSON

    connect(this, &MpvItem::wakeup, this, &MpvItem::drainEvents, Qt::QueuedConnection);
    mpv_set_wakeup_callback(m, [](void *ctx) { emit static_cast<MpvItem *>(ctx)->wakeup(); }, this);
}

MpvItem::~MpvItem() {
    setKeepAwake(false);
    mpv_set_wakeup_callback(core->mpv, nullptr, nullptr);
    {
        // After this returns libmpv makes no further update callbacks into us.
        std::lock_guard lock(core->glLock);
        if (core->gl) mpv_render_context_set_update_callback(core->gl, nullptr, nullptr);
    }
    command({"stop"});
}

QQuickFramebufferObject::Renderer *MpvItem::createRenderer() const {
    window()->setPersistentGraphics(true);
    window()->setPersistentSceneGraph(true);
    return new MpvRenderer(this);
}

void MpvItem::drainEvents() {
    while (auto *ev = mpv_wait_event(core->mpv, 0)) {
        switch (ev->event_id) {
        case MPV_EVENT_NONE:
            return;
        case MPV_EVENT_FILE_LOADED:
            m_lastError.clear();
            emit fileLoaded();
            break;
        case MPV_EVENT_PLAYBACK_RESTART:
            m_lastError.clear(); // decoder probing (e.g. a failed Vulkan hwdec) is behind us
            emit playbackRestart();
            break;
        case MPV_EVENT_END_FILE: {
            auto *ef = static_cast<mpv_event_end_file *>(ev->data);
            static const char *reasons[]{"eof", "", "stop", "quit", "error", "redirect"};
            QString reason = ef->reason >= 0 && ef->reason <= 5 ? reasons[ef->reason] : "error";
            QString error;
            if (ef->reason == MPV_END_FILE_REASON_ERROR)
                error = m_lastError.isEmpty() ? mpv_error_string(ef->error) : QString("%1: %2").arg(mpv_error_string(ef->error), m_lastError);
            m_lastError.clear();
            emit endFile(reason, error);
            break;
        }
        case MPV_EVENT_LOG_MESSAGE: {
            auto *msg = static_cast<mpv_event_log_message *>(ev->data);
            static const bool verbose = qEnvironmentVariableIsSet("AIKATSU_MPV_LOG");
            if (verbose)
                qWarning("[mpv/%s] %s", msg->prefix, QByteArray(msg->text).trimmed().constData());
            if (msg->log_level <= MPV_LOG_LEVEL_ERROR)
                m_lastError = QString::fromUtf8(msg->text).trimmed();
            break;
        }
        case MPV_EVENT_COMMAND_REPLY:
            if (ev->error < 0)
                qWarning("mpv command failed: %s", mpv_error_string(ev->error));
            break;
        case MPV_EVENT_PROPERTY_CHANGE: {
            auto *p = static_cast<mpv_event_property *>(ev->data);
            QByteArray name(p->name);
            auto dbl = [&](double &field, void (MpvItem::*sig)()) {
                double v = p->format == MPV_FORMAT_DOUBLE ? *static_cast<double *>(p->data) : 0;
                if (v != field) { field = v; emit (this->*sig)(); }
            };
            auto flag = [&](bool &field, void (MpvItem::*sig)()) {
                bool v = p->format == MPV_FORMAT_FLAG && *static_cast<int *>(p->data);
                if (v != field) { field = v; emit (this->*sig)(); }
            };
            if (name == "time-pos") dbl(m_position, &MpvItem::positionChanged);
            else if (name == "duration") dbl(m_duration, &MpvItem::durationChanged);
            else if (name == "demuxer-cache-time") dbl(m_cacheTime, &MpvItem::cacheTimeChanged);
            else if (name == "volume") dbl(m_volume, &MpvItem::volumeChanged);
            else if (name == "speed") dbl(m_speed, &MpvItem::speedChanged);
            else if (name == "pause") flag(m_paused, &MpvItem::pausedChanged);
            else if (name == "paused-for-cache") flag(m_buffering, &MpvItem::bufferingChanged);
            else if (name == "idle-active") flag(m_idle, &MpvItem::idleChanged);
            else if (name == "track-list") {
                m_trackList = p->format == MPV_FORMAT_STRING ? QString::fromUtf8(*static_cast<char **>(p->data)) : "[]";
                emit trackListChanged();
            }
            break;
        }
        default:
            break;
        }
    }
}

void MpvItem::command(const QStringList &args) {
    QList<QByteArray> utf8;
    std::vector<const char *> argv;
    for (const auto &a : args) utf8.append(a.toUtf8());
    for (const auto &a : utf8) argv.push_back(a.constData());
    argv.push_back(nullptr);
    // Qt's render thread waits for the GUI thread during scene synchronization.
    if (int err = mpv_command_async(core->mpv, 0, argv.data()); err < 0)
        qWarning("mpv command %s failed: %s", qPrintable(args.join(' ')), mpv_error_string(err));
}

void MpvItem::setProp(const QString &name, const QString &value) {
    command({"set", name, value});
}

QString MpvItem::getProp(const QString &name) const {
    char *v = mpv_get_property_string(core->mpv, name.toUtf8().constData());
    QString out = v ? QString::fromUtf8(v) : QString();
    mpv_free(v);
    return out;
}

void MpvItem::setKeepAwake(bool v) {
    if (v == m_keepAwake) return;
    m_keepAwake = v;
#ifdef Q_OS_WIN
    // Per thread; QML bindings and the destructor both run on the GUI thread.
    SetThreadExecutionState(v ? ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED : ES_CONTINUOUS);
#elif defined(Q_OS_LINUX)
    auto msg = QDBusMessage::createMethodCall("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver",
                                              v ? "Inhibit" : "UnInhibit");
    if (v) {
        QDBusReply<uint> reply = QDBusConnection::sessionBus().call(msg << QGuiApplication::applicationName() << QStringLiteral("Playing video"));
        if (reply.isValid()) m_inhibitCookie = reply.value();
        else qWarning("could not inhibit the screensaver: %s", qPrintable(reply.error().message()));
    } else if (m_inhibitCookie) {
        QDBusConnection::sessionBus().send(msg << *m_inhibitCookie);
        m_inhibitCookie.reset();
    }
#endif
}

void MpvItem::setPaused(bool v) { setProp("pause", v ? "yes" : "no"); }
void MpvItem::setVolume(double v) { setProp("volume", QString::number(v)); }
void MpvItem::setSpeed(double v) { setProp("speed", QString::number(v)); }

namespace {

// QML creates one manager per loading thread; each gets the same on-disk cache,
// so images survive restarts and show up when the network is flaky.
class CachingNamFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager *create(QObject *parent) override {
        auto *nam = new QNetworkAccessManager(parent);
        auto *cache = new QNetworkDiskCache(nam);
        cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/images");
        cache->setMaximumCacheSize(qint64(256) << 20);
        nam->setCache(cache);
        return nam;
    }
};

} // namespace

void aikatsu_engine_init(QQmlApplicationEngine &engine) {
    static CachingNamFactory factory;
    engine.setNetworkAccessManagerFactory(&factory);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &engine, [](QObject *object, const QUrl &) {
        if (auto *window = qobject_cast<QWindow *>(object)) {
            // No _q_has_border_in_fullscreen: the 1px border it adds shows as a line around the video. The cost is that
            // Windows may stop compositing other windows over the fullscreen GL window, see LogDrawer's export.
            new WindowState(window, QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation) + "/window.ini");
#ifdef Q_OS_WIN
            const auto hwnd = reinterpret_cast<HWND>(window->winId()); // created by WindowState's show()
            // Leaving fullscreen for maximized, Qt restores the normal geometry and then maximizes. With DWM's
            // restore and maximize animations the window visibly passes through its windowed size, so they are
            // off while fullscreen. Queued, so they come back only after Qt's state change has finished.
            QObject::connect(window, &QWindow::windowStateChanged, window, [hwnd](Qt::WindowState state) {
                const BOOL off = state == Qt::WindowFullScreen;
                DwmSetWindowAttribute(hwnd, DWMWA_TRANSITIONS_FORCEDISABLED, &off, sizeof off);
            }, Qt::QueuedConnection);
#endif
        }
    });
}

void aikatsu_init() {
    QGuiApplication::setApplicationName("Aikatsu");
    QGuiApplication::setDesktopFileName("aikatsu"); // Wayland app-id, matches aikatsu.desktop
    QGuiApplication::setWindowIcon(QIcon(":/icon.svg"));
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    std::setlocale(LC_NUMERIC, "C"); // libmpv requires the C numeric locale
}
