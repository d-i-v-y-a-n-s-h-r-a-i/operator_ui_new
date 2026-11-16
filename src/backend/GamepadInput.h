#pragma once

#include <QObject>
#include <QTimer>
#include "VesselState.h"
#include "TelemetryManager.h"

class GamepadInput : public QObject {
    Q_OBJECT
    Q_PROPERTY(double throttle READ throttle NOTIFY axesChanged)
    Q_PROPERTY(double rudder READ rudder NOTIFY axesChanged)
    Q_PROPERTY(double leftMix READ leftMix NOTIFY mixChanged)
    Q_PROPERTY(double rightMix READ rightMix NOTIFY mixChanged)
    Q_PROPERTY(double deadzone READ deadzone WRITE setDeadzone NOTIFY deadzoneChanged)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(int updateRateHz READ updateRateHz WRITE setUpdateRateHz NOTIFY updateRateChanged)

public:
    explicit GamepadInput(VesselState* state, TelemetryManager* telemetry, QObject* parent = nullptr);

    double throttle() const;
    double rudder() const;
    double leftMix() const;
    double rightMix() const;
    double deadzone() const;
    bool isActive() const;
    int updateRateHz() const;

public slots:
    void setVirtualInput(double throttle, double rudder);
    void setDeadzone(double deadzone);
    void setUpdateRateHz(int hz);
    void start();
    void stop();
    void emergencyStop();

signals:
    void axesChanged(double throttle, double rudder);
    void mixChanged(double left, double right);
    void deadzoneChanged(double deadzone);
    void activeChanged(bool active);
    void updateRateChanged(int hz);

private slots:
    void updateControlLoop();

private:
    double applyDeadzone(double val) const;
    void computeDifferentialMixing();

    VesselState* m_vesselState{nullptr};
    TelemetryManager* m_telemetry{nullptr};
    QTimer* m_loopTimer{nullptr};

    double m_throttle{0.0};
    double m_rudder{0.0};
    double m_leftMix{0.0};
    double m_rightMix{0.0};
    double m_deadzone{0.08};
    int m_updateRateHz{20};
    bool m_active{false};
};

