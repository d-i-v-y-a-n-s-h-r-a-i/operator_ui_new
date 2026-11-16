#pragma once

#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include "VesselState.h"
#include "TelemetryManager.h"
#include "MissionPlan.h"

class FailsafeMonitor : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool alarmActive READ isAlarmActive NOTIFY alarmStateChanged)
    Q_PROPERTY(QString alarmMessage READ alarmMessage NOTIFY alarmStateChanged)
    Q_PROPERTY(int alarmLevel READ alarmLevel NOTIFY alarmStateChanged)
    Q_PROPERTY(bool commsTimeout READ isCommsTimeout NOTIFY commsTimeoutChanged)
    Q_PROPERTY(int timeoutThresholdMs READ timeoutThresholdMs WRITE setTimeoutThresholdMs NOTIFY thresholdChanged)

public:
    enum AlarmLevel {
        None = 0,
        Warning = 1,
        Critical = 2,
        Emergency = 3
    };
    Q_ENUM(AlarmLevel)

    explicit FailsafeMonitor(VesselState* state, TelemetryManager* telemetry, MissionPlan* mission, QObject* parent = nullptr);

    bool isAlarmActive() const;
    QString alarmMessage() const;
    int alarmLevel() const;
    bool isCommsTimeout() const;
    int timeoutThresholdMs() const;

public slots:
    void notifyPacketReceived();
    void setTimeoutThresholdMs(int ms);
    void acknowledgeAlarm();
    void triggerManualEmergency();

signals:
    void alarmStateChanged();
    void commsTimeoutChanged(bool timeout);
    void thresholdChanged(int ms);
    void emergencyActionTriggered(const QString& action);

private slots:
    void checkWatchdog();

private:
    void evaluateSafetyRules();

    VesselState* m_vesselState{nullptr};
    TelemetryManager* m_telemetry{nullptr};
    MissionPlan* m_missionPlan{nullptr};
    QTimer* m_watchdogTimer{nullptr};
    QElapsedTimer m_lastHeartbeatTimer;

    int m_timeoutThresholdMs{1500};
    bool m_commsTimeout{false};
    bool m_alarmActive{false};
    QString m_alarmMessage{""};
    int m_alarmLevel{None};
    bool m_acknowledged{false};
};

