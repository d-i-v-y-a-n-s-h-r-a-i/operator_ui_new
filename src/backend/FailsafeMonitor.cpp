#include "FailsafeMonitor.h"

FailsafeMonitor::FailsafeMonitor(VesselState* state, TelemetryManager* telemetry, MissionPlan* mission, QObject* parent)
    : QObject(parent), m_vesselState(state), m_telemetry(telemetry), m_missionPlan(mission) {
    m_watchdogTimer = new QTimer(this);
    connect(m_watchdogTimer, &QTimer::timeout, this, &FailsafeMonitor::checkWatchdog);
    m_lastHeartbeatTimer.start();
    m_watchdogTimer->start(200);

    if (m_telemetry) {
        connect(m_telemetry, &TelemetryManager::packetReceived, this, &FailsafeMonitor::notifyPacketReceived);
    }
}

bool FailsafeMonitor::isAlarmActive() const { return m_alarmActive; }
QString FailsafeMonitor::alarmMessage() const { return m_alarmMessage; }
int FailsafeMonitor::alarmLevel() const { return m_alarmLevel; }
bool FailsafeMonitor::isCommsTimeout() const { return m_commsTimeout; }
int FailsafeMonitor::timeoutThresholdMs() const { return m_timeoutThresholdMs; }

void FailsafeMonitor::notifyPacketReceived() {
    m_lastHeartbeatTimer.restart();
    if (m_commsTimeout) {
        m_commsTimeout = false;
        emit commsTimeoutChanged(false);
    }
}

void FailsafeMonitor::setTimeoutThresholdMs(int ms) {
    if (m_timeoutThresholdMs != ms && ms >= 200) {
        m_timeoutThresholdMs = ms;
        emit thresholdChanged(m_timeoutThresholdMs);
    }
}

void FailsafeMonitor::acknowledgeAlarm() {
    m_acknowledged = true;
    m_alarmActive = false;
    emit alarmStateChanged();
}

void FailsafeMonitor::triggerManualEmergency() {
    m_alarmActive = true;
    m_alarmLevel = Emergency;
    m_alarmMessage = "MANUAL EMERGENCY STOP TRIGGERED";
    emit alarmStateChanged();
    emit emergencyActionTriggered("ESTOP");
    if (m_telemetry) {
        m_telemetry->sendEmergencyStop();
    }
}

void FailsafeMonitor::checkWatchdog() {
    qint64 elapsed = m_lastHeartbeatTimer.elapsed();
    if (elapsed > m_timeoutThresholdMs && !m_commsTimeout) {
        m_commsTimeout = true;
        emit commsTimeoutChanged(true);
        if (m_vesselState && m_vesselState->armed()) {
            m_vesselState->setLinkQuality(0);
        }
    }
    evaluateSafetyRules();
}

void FailsafeMonitor::evaluateSafetyRules() {
    if (!m_vesselState) return;

    bool newAlarmActive = false;
    QString newMessage = "";
    int newLevel = None;

    if (m_vesselState->leakDetected()) {
        newAlarmActive = true;
        newLevel = Emergency;
        newMessage = "BILGE LEAK DETECTED - BILGE PUMP ENGAGED";
    } else if (m_vesselState->coolantTemp() > 92.0) {
        newAlarmActive = true;
        newLevel = Emergency;
        newMessage = "CRITICAL ENGINE OVERHEAT - EXHAUST SEAL PROTECTION ESTOP";
    } else if (m_vesselState->coolantTemp() > 80.0) {
        newAlarmActive = true;
        newLevel = Warning;
        newMessage = "HIGH COOLANT TEMP - CHECK JET PUMP INTAKE";
    } else if (m_commsTimeout && m_vesselState->armed()) {
        newAlarmActive = true;
        newLevel = Critical;
        newMessage = "TELEMETRY LINK TIMEOUT - VESSEL IN FAILSAFE HOLD";
    } else if (m_vesselState->batteryPercentage() < 15) {
        newAlarmActive = true;
        newLevel = Critical;
        newMessage = "CRITICAL BATTERY LEVEL - RETURN TO LAUNCH RECOMMENDED";
    } else if (m_vesselState->batteryPercentage() < 25) {
        newAlarmActive = true;
        newLevel = Warning;
        newMessage = "LOW BATTERY WARNING";
    } else if (m_vesselState->batteryTemp() > 55.0) {
        newAlarmActive = true;
        newLevel = Warning;
        newMessage = "HIGH BATTERY PACK TEMPERATURE";
    }

    if (newAlarmActive && (!m_alarmActive || m_alarmMessage != newMessage)) {
        m_alarmActive = true;
        m_alarmMessage = newMessage;
        m_alarmLevel = newLevel;
        m_acknowledged = false;
        emit alarmStateChanged();

        if (newLevel == Emergency && m_telemetry) {
            emit emergencyActionTriggered("ESTOP");
            m_telemetry->sendEmergencyStop();
        }
    } else if (!newAlarmActive && m_alarmActive) {
        m_alarmActive = false;
        m_alarmMessage = "";
        m_alarmLevel = None;
        emit alarmStateChanged();
    }
}

