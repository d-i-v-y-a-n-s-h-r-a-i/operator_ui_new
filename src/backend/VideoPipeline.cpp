#include "VideoPipeline.h"

VideoPipeline::VideoPipeline(QObject* parent) : QObject(parent) {
    m_player = new QMediaPlayer(this);
    m_audioOutput = new QAudioOutput(this);
    m_player->setAudioOutput(m_audioOutput);
    m_audioOutput->setMuted(true);

    connect(m_player, &QMediaPlayer::playbackStateChanged, this, [this](QMediaPlayer::PlaybackState state) {
        bool playing = (state == QMediaPlayer::PlayingState);
        if (m_isPlaying != playing) {
            m_isPlaying = playing;
            emit playStateChanged(m_isPlaying);
        }
    });

    connect(m_player, &QMediaPlayer::errorOccurred, this, [this](QMediaPlayer::Error error, const QString& errorString) {
        Q_UNUSED(error);
        emit errorOccurred(errorString);
    });
}

QUrl VideoPipeline::sourceUrl() const { return m_sourceUrl; }
bool VideoPipeline::isPlaying() const { return m_isPlaying; }
int VideoPipeline::fps() const { return m_fps; }
int VideoPipeline::bitrateKbps() const { return m_bitrateKbps; }
QSize VideoPipeline::resolution() const { return m_resolution; }
QString VideoPipeline::pipelineString() const { return m_pipelineString; }

void VideoPipeline::setSourceUrl(const QUrl& url) {
    if (m_sourceUrl != url) {
        m_sourceUrl = url;
        emit sourceUrlChanged(m_sourceUrl);
        if (m_isPlaying) {
            m_player->setSource(m_sourceUrl);
            m_player->play();
        }
    }
}

void VideoPipeline::setPipelineString(const QString& pipeline) {
    if (m_pipelineString != pipeline) {
        m_pipelineString = pipeline;
        emit pipelineChanged(m_pipelineString);
    }
}

void VideoPipeline::setVideoSink(QVideoSink* sink) {
    if (m_videoSink != sink) {
        m_videoSink = sink;
        if (m_player) {
            m_player->setVideoSink(m_videoSink);
        }
    }
}

void VideoPipeline::play() {
    if (!m_sourceUrl.isEmpty()) {
        m_player->setSource(m_sourceUrl);
        m_player->play();
        m_isPlaying = true;
        emit playStateChanged(true);
    }
}

void VideoPipeline::pause() {
    m_player->pause();
    m_isPlaying = false;
    emit playStateChanged(false);
}

void VideoPipeline::stop() {
    m_player->stop();
    m_isPlaying = false;
    emit playStateChanged(false);
}

void VideoPipeline::restart() {
    stop();
    play();
}

void VideoPipeline::setStats(int fps, int bitrateKbps, int width, int height) {
    bool statsChangedFlag = false;
    if (m_fps != fps || m_bitrateKbps != bitrateKbps) {
        m_fps = fps;
        m_bitrateKbps = bitrateKbps;
        statsChangedFlag = true;
    }
    if (m_resolution.width() != width || m_resolution.height() != height) {
        m_resolution = QSize(width, height);
        emit resolutionChanged(m_resolution);
    }
    if (statsChangedFlag) {
        emit statsChanged();
    }
}
