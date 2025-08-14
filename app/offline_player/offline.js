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
                this.showStatus('No videos available', 3000);
            }
        } catch (error) {
            console.error('Failed to load videos:', error);
            this.showStatus('Error loading videos', 5000);
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
        const videoPath = `/opt/fireplace/videos/${video.filename}`;
        
        videoElement.src = `file://${videoPath}`;
        videoElement.volume = this.muted ? 0 : this.volume / 100;
        videoElement.muted = this.muted;
        
        console.log(`Loading video: ${video.filename}`);
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
    
    setupEventListeners() {
        this.currentVideo.addEventListener('ended', () => {
            if (!this.isTransitioning) {
                this.transitionToNext();
            }
        });
        
        this.currentVideo.addEventListener('error', (e) => {
            console.error('Video playback error:', e);
            this.showStatus('Video playback error', 3000);
            setTimeout(() => this.transitionToNext(), 1000);
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