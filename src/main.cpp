#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include "VesselState.h"
#include "MissionPlan.h"
#include "TelemetryManager.h"
#include "GamepadInput.h"
#include "VideoPipeline.h"
#include "FailsafeMonitor.h"

int main(int argc, char* argv[]) {
    QGuiApplication::setApplicationName("Tandav_GCS");
    QGuiApplication::setOrganizationName("Ci4");
    QGuiApplication::setOrganizationDomain("ci4.defense");

    QQuickStyle::setStyle("Basic");

    QGuiApplication app(argc, argv);

    auto* vesselState = VesselState::instance();
    auto* missionPlan = new MissionPlan(&app);
    auto* telemetry = new TelemetryManager(vesselState, missionPlan, &app);
    auto* gamepad = new GamepadInput(vesselState, telemetry, &app);
    auto* video = new VideoPipeline(&app);
    auto* failsafe = new FailsafeMonitor(vesselState, telemetry, missionPlan, &app);

    qmlRegisterSingletonInstance<VesselState>("Tandav.Models", 1, 0, "VesselState", vesselState);

    QObject::connect(vesselState, &VesselState::videoSinkChanged, [vesselState, video]() {
        video->setVideoSink(vesselState->videoSink());
    });

    telemetry->startListening();
    gamepad->start();

    QQmlApplicationEngine engine;

    engine.rootContext()->setContextProperty("vesselState", vesselState);
    engine.rootContext()->setContextProperty("missionPlan", missionPlan);
    engine.rootContext()->setContextProperty("telemetry", telemetry);
    engine.rootContext()->setContextProperty("gamepad", gamepad);
    engine.rootContext()->setContextProperty("video", video);
    engine.rootContext()->setContextProperty("failsafe", failsafe);

    const QUrl url(QStringLiteral("qrc:/qml/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject* obj, const QUrl& objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}
