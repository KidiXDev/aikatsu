#ifndef AIKATSU_WINDOWSTATE_H
#define AIKATSU_WINDOWSTATE_H

#include <QtCore/QSettings>
#include <QtGui/QGuiApplication>
#include <QtGui/QScreen>
#include <QtGui/QWindow>

class WindowState : public QObject {
    QWindow *window;
    QSettings settings;
    QRect normal;
    bool maximized;

    bool pip() const { return window->property("pip").toBool(); }

    void rememberGeometry() {
        if (window->windowState() == Qt::WindowNoState && !pip())
            normal = window->geometry();
        window->setProperty("normalGeometry", QRectF(normal));
    }

public:
    WindowState(QWindow *w, const QString &path)
        : QObject(w), window(w), settings(path, QSettings::IniFormat),
          normal(settings.value("geometry").toRect()), maximized(settings.value("maximized", false).toBool()) {
        if (normal.isValid()) {
            window->create();
            auto *screen = QGuiApplication::screenAt(normal.center());
            if (!screen) screen = window->screen();
            if (screen) {
                const auto available = screen->availableGeometry().marginsRemoved(window->frameMargins());
                normal.setSize(normal.size().boundedTo(available.size()).expandedTo(window->minimumSize()));
                normal.moveLeft(qBound(available.left(), normal.x(), qMax(available.left(), available.right() - normal.width() + 1)));
                normal.moveTop(qBound(available.top(), normal.y(), qMax(available.top(), available.bottom() - normal.height() + 1)));
            }
            window->setGeometry(normal);
        } else {
            normal = window->geometry();
        }
        window->setProperty("normalGeometry", QRectF(normal));
        // Wait for maximize/fullscreen transitions to settle before recording bounds.
        connect(window, &QWindow::xChanged, this, &WindowState::rememberGeometry, Qt::QueuedConnection);
        connect(window, &QWindow::yChanged, this, &WindowState::rememberGeometry, Qt::QueuedConnection);
        connect(window, &QWindow::widthChanged, this, &WindowState::rememberGeometry, Qt::QueuedConnection);
        connect(window, &QWindow::heightChanged, this, &WindowState::rememberGeometry, Qt::QueuedConnection);
        connect(window, &QWindow::windowStateChanged, this, [this](Qt::WindowState state) {
            if (!pip() && (state == Qt::WindowNoState || state == Qt::WindowMaximized))
                maximized = state == Qt::WindowMaximized;
        });
        connect(qGuiApp, &QCoreApplication::aboutToQuit, this, &WindowState::save);
        if (maximized) window->showMaximized();
        else window->show();
    }

    void save() {
        rememberGeometry();
        settings.setValue("geometry", normal);
        settings.setValue("maximized", maximized);
        settings.sync();
        if (settings.status() != QSettings::NoError)
            qWarning("could not save window state");
    }
};

#endif
