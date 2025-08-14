class OfflinePlayer {
    constructor() {
        this.currentVideo = document.getElementById('current-video');
        this.nextVideo = document.getElementById('next-video');
        this.status = document.getElementById('status');
        
        this.videos = [];
        this.currentIndex = 0;
        this.isTransitioning = false;
        this.pollInterval = 5000; // 5 seconds
        
        this.init();
    }
    
    async init() {
        console.log('Initializing offline player...');
        await this.loadState();
        await this.loadVideos();
        this.setupEventListeners();
        this.startStatePolling();
        this.hideStatus();
    }
    
    async loadState() {
        try {
            const response = await fetch('/api/state');
            const state = await response.json();
            
            this.volume = state.volume || 60;
            this.muted = state.muted !== undefined ? state.muted : true;
            this.selectedVideo = state.selected_offline;
            this.activePlaylist = state.active_playlist || 'default';
            this.playlists = state.playlists || { default: [] };
            
            console.log('State loaded:', state);
        } catch (error) {
            console.error('Failed to load state:', error);
            this.volume = 60;
            this.muted = true;
        }
    }
    
    async loadVideos() {
        try {
            const response = await fetch('/api/videos');
            const data = await response.json();
            this.videos = data.videos || [];
            
            console.log(`Loaded ${this.videos.length} videos`);
            
            if (this.videos.length > 0) {
                this.startPlayback();
            } else {
                this.showStatus('No videos available - Please add videos to /opt/fireplace/videos/', 5000);
                this.showNoVideosMessage();
            }
        } catch (error) {
            console.error('Failed to load videos:', error);
            this.showStatus('Error loading videos', 5000);
            this.showNoVideosMessage();
        }
    }
    
    startPlayback() {
        if (this.videos.length === 0) return;
        
        // Find the selected video index
        if (this.selectedVideo) {
            const index = this.videos.findIndex(v => v.filename === this.selectedVideo);
            if (index !== -1) {
                this.currentIndex = index;
            }
        }
        
        this.loadVideoIntoPlayer(this.currentVideo, this.currentIndex);
        this.preloadNextVideo();
        
        this.showStatus(`Playing: ${this.videos[this.currentIndex].filename}`, 3000);
    }
    
    loadVideoIntoPlayer(videoElement, index) {
        if (index < 0 || index >= this.videos.length) return;
        
        const video = this.videos[index];
        // Use HTTP URL to serve video through Flask
        const videoPath = `/videos/${encodeURIComponent(video.filename)}`;
        
        videoElement.src = videoPath;
        videoElement.volume = this.muted ? 0 : this.volume / 100;
        videoElement.muted = this.muted;
        
        console.log(`Loading video: ${video.filename} from ${videoPath}`);
        
        // Try to play automatically
        videoElement.play().catch(e => {
            console.log('Autoplay failed:', e);
            this.showStatus('Click anywhere to start playback', 5000);
            
            // Add one-time click handler to start playback
            const startPlayback = () => {
                videoElement.play().catch(err => console.error('Play failed:', err));
                document.removeEventListener('click', startPlayback);
            };
            document.addEventListener('click', startPlayback);
        });
    }
    
    preloadNextVideo() {
        const nextIndex = this.getNextVideoIndex();
        this.loadVideoIntoPlayer(this.nextVideo, nextIndex);
    }
    
    getNextVideoIndex() {
        if (this.videos.length <= 1) return this.currentIndex;
        
        // If we have a playlist and it's not just one video, cycle through it
        const playlist = this.playlists[this.activePlaylist];
        if (playlist && playlist.length > 1) {
            const currentVideoName = this.videos[this.currentIndex].filename;
            const playlistIndex = playlist.indexOf(currentVideoName);
            if (playlistIndex !== -1) {
                const nextPlaylistIndex = (playlistIndex + 1) % playlist.length;
                const nextVideoName = playlist[nextPlaylistIndex];
                const nextIndex = this.videos.findIndex(v => v.filename === nextVideoName);
                if (nextIndex !== -1) return nextIndex;
            }
        }
        
        // Default: cycle through all videos
        return (this.currentIndex + 1) % this.videos.length;
    }
    
    showNoVideosMessage() {
        // Display a message on the video element
        const container = document.getElementById('video-container');
        container.innerHTML = `
            <div style="display: flex; align-items: center; justify-content: center; height: 100vh; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-align: center; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
                <div>
                    <h1 style="font-size: 48px; margin-bottom: 20px;">🔥 No Videos Available</h1>
                    <p style="font-size: 24px; margin-bottom: 40px;">Please add video files to:</p>
                    <code style="background: rgba(0,0,0,0.3); padding: 10px 20px; border-radius: 5px; font-size: 20px;">/opt/fireplace/videos/</code>
                    <p style="font-size: 16px; margin-top: 40px; opacity: 0.8;">Supported formats: MP4, WebM, MKV, AVI, MOV</p>
                </div>
            </div>
        `;
    }
    
    setupEventListeners() {
        this.currentVideo.addEventListener('ended', () => {
            if (!this.isTransitioning && this.videos.length > 0) {
                this.transitionToNext();
            }
        });
        
        this.currentVideo.addEventListener('error', (e) => {
            console.error('Video playback error:', e);
            const videoSrc = e.target.src;
            
            // More detailed error message
            let errorMsg = 'Video playback error';
            if (videoSrc.includes('/videos/')) {
                const filename = videoSrc.split('/videos/')[1];
                errorMsg = `Cannot play video: ${decodeURIComponent(filename)}`;
            }
            
            this.showStatus(errorMsg, 3000);
            
            // Only try next video if we have more videos
            if (this.videos.length > 1) {
                setTimeout(() => this.transitionToNext(), 1000);
            } else if (this.videos.length === 0) {
                this.showNoVideosMessage();
            }
        });
        
        this.nextVideo.addEventListener('canplaythrough', () => {
            console.log('Next video preloaded');
        });
        
        // Handle visibility changes (screensaver, etc.)
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden) {
                this.currentVideo.play().catch(e => console.log('Play failed:', e));
            }
        });
    }
    
    async transitionToNext() {
        if (this.isTransitioning || this.videos.length <= 1) return;
        
        this.isTransitioning = true;
        const nextIndex = this.getNextVideoIndex();
        
        console.log(`Transitioning from ${this.currentIndex} to ${nextIndex}`);
        
        // Fade out current video
        this.currentVideo.classList.add('fade-out');
        
        // Prepare next video
        this.nextVideo.style.display = 'block';
        this.nextVideo.classList.remove('fade-out');
        this.nextVideo.classList.add('fade-in');
        
        // Start next video
        try {
            await this.nextVideo.play();
        } catch (e) {
            console.error('Failed to play next video:', e);
        }
        
        // Wait for fade transition
        setTimeout(() => {
            // Swap videos
            const tempVideo = this.currentVideo;
            this.currentVideo = this.nextVideo;
            this.nextVideo = tempVideo;
            
            // Hide old video
            this.nextVideo.style.display = 'none';
            this.nextVideo.classList.remove('fade-in', 'fade-out');
            this.nextVideo.pause();
            this.nextVideo.currentTime = 0;
            
            // Update current index
            this.currentIndex = nextIndex;
            
            // Preload next video
            this.preloadNextVideo();
            
            this.isTransitioning = false;
            
            this.showStatus(`Now playing: ${this.videos[this.currentIndex].filename}`, 2000);
        }, 1000);
    }
    
    async updateFromState(newState) {
        let needsRestart = false;
        
        // Check volume changes
        if (newState.volume !== this.volume) {
            this.volume = newState.volume;
            this.currentVideo.volume = this.muted ? 0 : this.volume / 100;
            this.nextVideo.volume = this.muted ? 0 : this.volume / 100;
            console.log(`Volume updated to ${this.volume}`);
        }
        
        // Check mute changes
        if (newState.muted !== this.muted) {
            this.muted = newState.muted;
            this.currentVideo.muted = this.muted;
            this.nextVideo.muted = this.muted;
            this.currentVideo.volume = this.muted ? 0 : this.volume / 100;
            this.nextVideo.volume = this.muted ? 0 : this.volume / 100;
            console.log(`Mute updated to ${this.muted}`);
        }
        
        // Check video selection changes
        if (newState.selected_offline !== this.selectedVideo) {
            this.selectedVideo = newState.selected_offline;
            const newIndex = this.videos.findIndex(v => v.filename === this.selectedVideo);
            if (newIndex !== -1 && newIndex !== this.currentIndex) {
                this.currentIndex = newIndex;
                needsRestart = true;
                console.log(`Video selection changed to ${this.selectedVideo}`);
            }
        }
        
        // Check playlist changes
        if (JSON.stringify(newState.playlists) !== JSON.stringify(this.playlists)) {
            this.playlists = newState.playlists || { default: [] };
            this.activePlaylist = newState.active_playlist || 'default';
            this.preloadNextVideo(); // Update next video based on new playlist
            console.log(`Playlist updated`);
        }
        
        if (needsRestart) {
            this.restartPlayback();
        }
    }
    
    restartPlayback() {
        console.log('Restarting playback...');
        this.isTransitioning = false;
        this.currentVideo.classList.remove('fade-out', 'fade-in');
        this.nextVideo.classList.remove('fade-out', 'fade-in');
        this.nextVideo.style.display = 'none';
        
        this.loadVideoIntoPlayer(this.currentVideo, this.currentIndex);
        this.currentVideo.play().catch(e => console.log('Play failed:', e));
        this.preloadNextVideo();
        
        this.showStatus(`Switched to: ${this.videos[this.currentIndex].filename}`, 3000);
    }
    
    startStatePolling() {
        setInterval(async () => {
            try {
                const response = await fetch('/api/state');
                const newState = await response.json();
                await this.updateFromState(newState);
            } catch (error) {
                console.error('Failed to poll state:', error);
            }
        }, this.pollInterval);
    }
    
    showStatus(message, duration = 2000) {
        this.status.querySelector('.status-text').textContent = message;
        this.status.classList.add('show');
        
        setTimeout(() => {
            this.status.classList.remove('show');
        }, duration);
    }
    
    hideStatus() {
        setTimeout(() => {
            this.status.classList.remove('show');
        }, 3000);
    }
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', () => {
    new OfflinePlayer();
});

// Handle page errors
window.addEventListener('error', (e) => {
    console.error('Page error:', e.error);
});

// Prevent right-click context menu in kiosk mode
document.addEventListener('contextmenu', (e) => {
    e.preventDefault();
});

// Hide cursor after inactivity (for kiosk mode)
let cursorTimeout;
function hideCursor() {
    document.body.style.cursor = 'none';
}

function showCursor() {
    document.body.style.cursor = 'default';
    clearTimeout(cursorTimeout);
    cursorTimeout = setTimeout(hideCursor, 3000);
}

document.addEventListener('mousemove', showCursor);
document.addEventListener('keydown', showCursor);

// Initially hide cursor
setTimeout(hideCursor, 3000);