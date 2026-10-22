#ifndef AIKATSU_MPVITEM_H
#define AIKATSU_MPVITEM_H

#include <QtQml/QQmlApplicationEngine>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickFramebufferObject>
#include <memory>
#include <mutex>
#include <optional>

#include <mpv/client.h>
#include <mpv/render_gl.h>

// Shared by the item (GUI thread) and its renderer (render thread); whoever
// dies last tears mpv down, so the render context is always freed first.
struct MpvCore {
    mpv_handle *mpv = nullptr;
    mpv_render_context *gl = nullptr;
    std::mutex glLock; // item dtor (GUI) vs renderer dtor (render thread)
    ~MpvCore();
};

class MpvItem : public QQuickFramebufferObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(double cacheTime READ cacheTime NOTIFY cacheTimeChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(bool buffering READ buffering NOTIFY bufferingChanged)
    Q_PROPERTY(bool idle READ idle NOTIFY idleChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged)
    Q_PROPERTY(QString trackList READ trackList NOTIFY trackListChanged)
    // true once the GL render context exists; loading a file before that leaves mpv without a video output
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    // Holds off the screensaver and sleep. mpv's stop-screensaver needs a VO window, which the render API has none of.
    Q_PROPERTY(bool keepAwake READ keepAwake WRITE setKeepAwake)

public:
    explicit MpvItem(QQuickItem *parent = nullptr);
    ~MpvItem() override;
    Renderer *createRenderer() const override;

    double position() const { return m_position; }
    double duration() const { return m_duration; }
    double cacheTime() const { return m_cacheTime; }
    bool paused() const { return m_paused; }
    bool buffering() const { return m_buffering; }
    bool idle() const { return m_idle; }
    double volume() const { return m_volume; }
    double speed() const { return m_speed; }
    QString trackList() const { return m_trackList; }
    bool ready() const { return m_ready; }
    void markReady() { if (!m_ready) { m_ready = true; emit readyChanged(); } }
    bool keepAwake() const { return m_keepAwake; }
    void setKeepAwake(bool v);
    void setPaused(bool v);
    void setVolume(double v);
    void setSpeed(double v);

    Q_INVOKABLE void command(const QStringList &args);
    Q_INVOKABLE void setProp(const QString &name, const QString &value);
    Q_INVOKABLE QString getProp(const QString &name) const;

    std::shared_ptr<MpvCore> core;

signals:
    void positionChanged();
    void durationChanged();
    void cacheTimeChanged();
    void pausedChanged();
    void bufferingChanged();
    void idleChanged();
    void volumeChanged();
    void speedChanged();
    void trackListChanged();
    void readyChanged();
    void fileLoaded();
    // First frame after a load or seek.
    void playbackRestart();
    // reason: eof | stop | quit | error | redirect; error carries mpv's message
    // plus its last error log line (e.g. "HTTP error 403 Forbidden")
    void endFile(const QString &reason, const QString &error);
    void wakeup();

private:
    void drainEvents();
    QString m_lastError;
    double m_position = 0, m_duration = 0, m_cacheTime = 0, m_volume = 100, m_speed = 1;
    bool m_paused = false, m_buffering = false, m_idle = true, m_ready = false, m_keepAwake = false;
    QString m_trackList;
    std::optional<uint> m_inhibitCookie; // org.freedesktop.ScreenSaver on Linux, an IOPMAssertionID on macOS
};

// Must run after QGuiApplication exists and before any window is created.
void aikatsu_init();
// Before the engine loads anything: covers and banners go through a disk cache.
void aikatsu_engine_init(QQmlApplicationEngine &engine);
#endif
