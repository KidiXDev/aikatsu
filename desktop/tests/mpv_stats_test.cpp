#include "mpvitem.h"
#include <QtCore/QTimer>
#include <QtGui/QGuiApplication>
#include <QtQuick/QQuickWindow>
#include <QtQml/QQmlComponent>
#include <cstdio>

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QQuickWindow window;
    window.resize(640, 360);
    window.setTitle("Aikatsu mpv stats regression test");
    qmlRegisterType<MpvItem>("AikatsuTest", 1, 0, "MpvItem");
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData("import QtQuick\nimport AikatsuTest 1.0\nMpvItem { width: 640; height: 360 }", QUrl());
    auto *player = qobject_cast<MpvItem *>(component.create());
    if (!player) return 1;
    player->setParent(window.contentItem());
    player->setParentItem(window.contentItem());
    // Stats queries renderer information; software rendering doesn't exercise that request.
    QObject::connect(player, &MpvItem::readyChanged, player, [player] {
        std::fprintf(stderr, "Renderer ready\n");
        player->setProp("hwdec", "no");
        player->setProp("load-stats-overlay", "yes");
        player->command({"loadfile", "av://lavfi:testsrc2=size=640x360:rate=30"});
    });
    QObject::connect(player, &MpvItem::endFile, player, [](const QString &reason, const QString &error) {
        std::fprintf(stderr, "Playback ended: %s %s\n", qPrintable(reason), qPrintable(error));
    });
    bool stats = false;
    double position = 0;
    QObject::connect(player, &MpvItem::positionChanged, player, [&] {
        if (stats || player->position() < 0.3) return;
        stats = true;
        position = player->position();
        std::fprintf(stderr, "Opening stats during playback\n");
        player->command({"script-binding", "stats/display-stats"});
        QTimer::singleShot(4500, player, [player] { player->command({"script-binding", "stats/display-stats-toggle"}); });
        QTimer::singleShot(5000, player, [&, player] {
            player->command({"script-binding", "stats/display-stats-toggle"});
            player->setProp("pause", "no");
            player->command({"seek", "1", "relative"});
            QTimer::singleShot(500, player, [&, player] {
                player->command({"script-binding", "stats/display-stats-toggle"});
                QTimer::singleShot(500, player, [&, player] {
                    player->setProp("load-stats-overlay", "no");
                    player->command({"show-text", "", "0"});
                    const bool advanced = player->position() > position + 3;
                    if (!advanced) std::fprintf(stderr, "Playback stopped after opening stats\n");
                    app.exit(advanced ? 0 : 1);
                });
            });
        });
    });
    QTimer::singleShot(12000, &app, [&] { std::fprintf(stderr, "Stats test timed out\n"); app.exit(1); });
    window.show();
    return app.exec();
}
