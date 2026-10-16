#include "windowstate.h"
#include <QtCore/QTemporaryDir>
#include <cassert>

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QTemporaryDir dir;
    assert(dir.isValid());
    const auto path = dir.filePath("window.ini");
    QSettings settings(path, QSettings::IniFormat);
    const auto available = app.primaryScreen()->availableGeometry();
    const QRect normal(available.topLeft() + QPoint(20, 30), QSize(400, 300));

    {
        QWindow window;
        window.setMinimumSize(QSize(320, 200));
        auto *state = new WindowState(&window, path);
        window.setGeometry(normal);
        app.processEvents();
        state->save();
        settings.sync();
        assert(settings.value("geometry").toRect() == normal);
        assert(!settings.value("maximized").toBool());

        window.showMaximized();
        window.setGeometry(available);
        app.processEvents();
        state->save();
        settings.sync();
        assert(settings.value("geometry").toRect() == normal);
        assert(settings.value("maximized").toBool());

        window.showFullScreen();
        app.processEvents();
        state->save();
        settings.sync();
        assert(settings.value("geometry").toRect() == normal);
        assert(settings.value("maximized").toBool());

        window.showMinimized();
        app.processEvents();
        state->save();
        settings.sync();
        assert(settings.value("geometry").toRect() == normal);
        assert(settings.value("maximized").toBool());
    }
    {
        QWindow window;
        auto *state = new WindowState(&window, path);
        assert(window.windowState() == Qt::WindowMaximized);
        state->save();
        settings.sync();
        assert(settings.value("geometry").toRect() == normal);
    }
    settings.setValue("maximized", false);
    settings.sync();
    {
        QWindow window;
        new WindowState(&window, path);
        assert(window.windowState() == Qt::WindowNoState);
        assert(window.geometry() == normal);
    }
    settings.setValue("geometry", QRect(-9000, -9000, 5000, 5000));
    settings.sync();
    {
        QWindow window;
        window.setMinimumSize(QSize(320, 200));
        new WindowState(&window, path);
        assert(available.contains(window.frameGeometry()));
    }
}
