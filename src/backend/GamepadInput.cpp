#include "GamepadInput.h"
#include <QtMath>
#include <algorithm>

GamepadInput::GamepadInput(VesselState* state, TelemetryManager* telemetry, QObject* parent)
    : QObject(parent), m_vesselState(state), m_telemetry(telemetry) {
    m_loopTimer = new QTimer(this);
    connect(m_loopTimer, &QTimer::timeout, this, &GamepadInput::updateControlLoop);
}

double GamepadInput::throttle() const { return m_throttle; }
double GamepadInput::rudder() const { return m_rudder; }
double GamepadInput::leftMix() const { return m_leftMix; }
double GamepadInput::rightMix() const { return m_rightMix; }
double GamepadInput::deadzone() const { return m_deadzone; }
bool GamepadInput::isActive() const { return m_active; }
int GamepadInput::updateRateHz() const { return m_updateRateHz; }

void GamepadInput::setDeadzone(double deadzone) {
    if (!qFuzzyCompare(m_deadzone, deadzone)) {
        m_deadzone = qBound(0.0, deadzone, 0.5);
        emit deadzoneChanged(m_deadzone);
    }
}

void GamepadInput::setUpdateRateHz(int hz) {
    if (m_updateRateHz != hz && hz >= 1 && hz <= 100) {
        m_updateRateHz = hz;
        if (m_active) {
            m_loopTimer->setInterval(1000 / m_updateRateHz);
        }
        emit updateRateChanged(m_updateRateHz);
    }
}

void GamepadInput::start() {
    m_active = true;
    m_loopTimer->start(1000 / m_updateRateHz);
    emit activeChanged(true);
}

void GamepadInput::stop() {
    m_active = false;
    m_loopTimer->stop();
    m_throttle = 0.0;
    m_rudder = 0.0;
    m_leftMix = 0.0;
    m_rightMix = 0.0;
    emit axesChanged(0.0, 0.0);
    emit mixChanged(0.0, 0.0);
    emit activeChanged(false);
}

void GamepadInput::setVirtualInput(double throttle, double rudder) {
    m_throttle = applyDeadzone(qBound(-1.0, throttle, 1.0));
    m_rudder = applyDeadzone(qBound(-1.0, rudder, 1.0));
    computeDifferentialMixing();
    emit axesChanged(m_throttle, m_rudder);
}

double GamepadInput::applyDeadzone(double val) const {
    if (qAbs(val) < m_deadzone) return 0.0;
    double sign = (val > 0.0) ? 1.0 : -1.0;
    return sign * ((qAbs(val) - m_deadzone) / (1.0 - m_deadzone));
}

void GamepadInput::computeDifferentialMixing() {
    double left = m_throttle + m_rudder;
    double right = m_throttle - m_rudder;

    m_leftMix = qBound(-1.0, left, 1.0);
    m_rightMix = qBound(-1.0, right, 1.0);

    if (m_vesselState && m_vesselState->armed()) {
        m_vesselState->setThrusters(m_leftMix, m_rightMix);
    }
    emit mixChanged(m_leftMix, m_rightMix);
}

void GamepadInput::updateControlLoop() {
    if (!m_active || !m_telemetry || !m_vesselState) return;

    if (m_vesselState->armed() && m_vesselState->mode() == "TELEOP") {
        m_telemetry->sendControlPacket(m_leftMix, m_rightMix, true, "TELEOP");
    }
}

void GamepadInput::emergencyStop() {
    m_throttle = 0.0;
    m_rudder = 0.0;
    m_leftMix = 0.0;
    m_rightMix = 0.0;
    emit axesChanged(0.0, 0.0);
    emit mixChanged(0.0, 0.0);
    if (m_telemetry) {
        m_telemetry->sendEmergencyStop();
    }
}

