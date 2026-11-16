#pragma once

#include <QObject>
#include <QUdpSocket>
#include <QHostAddress>
#include <QTimer>
#include <QElapsedTimer>
#include "VesselState.h"
#include "MissionPlan.h"

#pragma pack(push, 1)
struct CanFramePacket {
    uint32_t canId;
    uint8_t dlc;
    uint8_t payload[8];
    uint32_t timestampMs;
};
#pragma pack(pop)

class TelemetryManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectionChanged)
    Q_PROPERTY(QString hostAddress READ hostAddress WRITE setHostAddress NOTIFY networkConfigChanged)
    Q_PROPERTY(quint16 port READ port WRITE setPort NOTIFY networkConfigChanged)
    Q_PROPERTY(quint16 sendPort READ sendPort WRITE setSendPort NOTIFY networkConfigChanged)

public:
    explicit TelemetryManager(VesselState* state, MissionPlan* mission, QObject* parent = nullptr);

    bool isConnected() const;
    QString hostAddress() const;
    quint16 port() const;
    quint16 sendPort() const;

public slots:
    void setHostAddress(const QString& address);
    void setPort(quint16 port);
    void setSendPort(quint16 port);
    bool startListening();
    void stopListening();
    void sendControlPacket(double leftThruster, double rightThruster, bool armed, const QString& mode);
    void sendArmDisarm(bool arm);
    void sendMode(const QString& mode);
    void sendEmergencyStop();
    void uploadMission();
    void sendPidGains(double kpHdg, double kiHdg, double kdHdg, double kpSpd, double kiSpd, double kdSpd);
    void sendTargetSpeed(double speed);
    void sendTargetHeading(double heading);

signals:
    void connectionChanged(bool connected);
    void networkConfigChanged();
    void packetReceived();
    void packetSent();
    void errorOccurred(const QString& error);

private slots:
    void readPendingDatagrams();
    void sendHeartbeat();

private:
    void parseTelemetryJson(const QByteArray& data);
    void parseTelemetryBinary(const QByteArray& data);
    void parseCanBusFrame(const QByteArray& data);

    VesselState* m_vesselState{nullptr};
    MissionPlan* m_missionPlan{nullptr};
    QUdpSocket* m_socket{nullptr};
    QTimer* m_heartbeatTimer{nullptr};
    QElapsedTimer m_lastPacketTimer;

    QHostAddress m_targetHost{QHostAddress::LocalHost};
    quint16 m_listenPort{9001};
    quint16 m_targetPort{9000};
    quint32 m_packetSequence{0};
    bool m_connected{false};
};
