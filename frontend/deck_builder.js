function getResourceIcon(type, fallback) {
    const resourceIcons = {
        water: '💧',
        food: '🍖',
        stone: '🪨',
        tool: '🔨',
        knowledge: '📚',
        copper: '🟫',
        tin: '⚪',
        bronze: '🥉',
        iron: '⛓️',
        gold: '🥇',
        concrete: '🧱',
        skill: '💪',
        mechanical: '⚙️',
        steel: '🔩',
        navigation: '🧭',
        gunpowder: '💥',
        printing: '📰',
        ships: '🚢',
        exotic_goods: '💎',
        culture: '🎭',
        coal: '⬛',
        steam: '♨️',
        transport: '🚛',
        electricity: '🔌',
        chemistry: '🧪',
        oil: '🛢️',
        plastics: '🔸',
        uranium: '☢️',
        electronics: '📱',
        computers: '💻',
        rockets: '🚀',
        advanced_materials: '✨',
        energy: '⚡',
        bandwidth: '📡',
        personalization: '👤',
        ai_cores: '🤖',
        nanotech: '⚛️',
        fusion: '☀️'
    };
    return resourceIcons[type] || fallback || '📦';
}

class DeckBuilder {
    constructor() {
        this.sessionId = null;
        this.cardCollection = [];
        this.currentDeck = [];
        this.selectedCards = new Set(); // Track selected card UUIDs
        
        this.extractSessionFromUrl();
        this.initializeEventListeners();
        this.loadData();
    }

    extractSessionFromUrl() {
        // Extract session ID from URL hash (e.g., #session_id=12345)
        const hash = window.location.hash.substring(1); // Remove the '#'
        const hashParams = new URLSearchParams(hash);
        this.sessionId = hashParams.get('session_id');
        
        if (!this.sessionId) {
            this.updateStatus('No session ID provided. Please start from the main game.');
            this.showError('Missing session ID in URL');
            return;
        }
    }

    initializeEventListeners() {
        document.getElementById('clear-deck-btn').addEventListener('click', () => this.clearDeck());
        document.getElementById('submit-deck-btn').addEventListener('click', () => this.submitDeck());
        document.getElementById('back-to-game-btn').addEventListener('click', () => this.backToGame());
        document.getElementById('upload-card-btn').addEventListener('click', () => this.triggerFileUpload());
        document.getElementById('card-file-input').addEventListener('change', (e) => this.handleFileUpload(e));
    }

    backToGame() {
        if (this.sessionId) {
            // Go back to game with session ID
            window.location.href = `/#session_id=${this.sessionId}`;
        } else {
            // Go back to game without session ID
            window.location.href = 'app.html';
        }
    }

    async loadData() {
        this.showLoading(true);
        this.updateStatus('Loading card collection and current deck...');
        
        try {
            // Load both card collection and current deck in parallel
            await Promise.all([
                this.loadCardCollection(),
                this.loadCurrentDeck()
            ]);
            
            this.updateUI();
            this.updateStatus('Ready to build your deck!');
            
        } catch (error) {
            console.error('Error loading data:', error);
            this.updateStatus('Failed to load deck builder data.');
            this.showError('Failed to load data: ' + error.message);
        } finally {
            this.showLoading(false);
        }
    }

    async loadCardCollection() {
        this.cardCollection = [];

        let offset = 0;
        const num = 50;
        while (true) {
            const response = await fetch(`/card_collection/${offset}`, {
                headers: { 'session-id': this.sessionId.toString() }
            });
            
            if (!response.ok) {
                if (response.status === 404 || response.status === 401) {
                    throw new Error('Invalid session. Please start a new game.');
                }
                throw new Error('Failed to load card collection');
            }
            
            const data = await response.json();
            if (data.cards.length === 0) {
                break;
            }
            if (data.cards.length < num) {
                break;
            }
            this.cardCollection.push(...data.cards);
            offset += num;
        }
    }

    async loadCurrentDeck() {
        try {
            const response = await fetch('/deck', {
                headers: { 'session-id': this.sessionId.toString() }
            });
            
            if (response.ok) {
                const deckData = await response.json();
                // Extract card UUIDs from the deck response - deckData.cards is array of UUIDs
                if (deckData && deckData.cards && Array.isArray(deckData.cards)) {
                    this.currentDeck = deckData.cards;
                    this.selectedCards = new Set(this.currentDeck);
                } else {
                    this.currentDeck = [];
                    this.selectedCards = new Set();
                }
            } else {
                // No existing deck or error loading it
                this.currentDeck = [];
                this.selectedCards = new Set();
            }
        } catch (error) {
            console.warn('Could not load current deck:', error);
            this.currentDeck = [];
            this.selectedCards = new Set();
        }
    }

    updateUI() {
        this.updateCardCollection();
        this.updateDeckDisplay();
        this.updateDeckStats();
        this.updateSubmitButton();
    }

    updateCardCollection() {
        const collectionGrid = document.getElementById('card-collection-grid');
        
        if (!this.cardCollection || this.cardCollection.length === 0) {
            collectionGrid.innerHTML = '<div class="placeholder">No cards available</div>';
            return;
        }
        
        collectionGrid.innerHTML = '';
        
        this.cardCollection.forEach(card => {
            const cardElement = this.createCardElement(card);
            collectionGrid.appendChild(cardElement);
        });
    }

    createCardElement(card) {
        const cardDiv = document.createElement('div');
        cardDiv.className = 'card';
        cardDiv.dataset.cardId = card.uuid;
        
        // Check if card is already in deck
        const isInDeck = this.selectedCards.has(card.uuid);
        if (isInDeck) {
            cardDiv.classList.add('disabled');
        }
        
        let statsHtml = '<div class="card-stats">';
        
        // Only show consumes if not "none"
        if (card.consumes && card.consumes.type !== 'none') {
            const consumesIcon = this.formatResourceType(card.consumes.type);
            const consumesName = this.formatResourceName(card.consumes.type);
            statsHtml += `
                <div class="card-stat">
                    <span class="stat-label">Consumes:</span>
                    <span class="stat-value consumes">${card.consumes.value} <span class="resource-icon-tooltip" title="${consumesName}">${consumesIcon}</span></span>
                </div>`;
        }
        
        // Only show produces if not "none"
        if (card.produces && card.produces.type !== 'none') {
            const producesIcon = this.formatResourceType(card.produces.type);
            const producesName = this.formatResourceName(card.produces.type);
            statsHtml += `
                <div class="card-stat">
                    <span class="stat-label">Produces:</span>
                    <span class="stat-value produces">${card.produces.value} <span class="resource-icon-tooltip" title="${producesName}">${producesIcon}</span></span>
                </div>`;
        }
        
        statsHtml += '</div>';
        
        cardDiv.innerHTML = `
            <div class="card-header">
                <div class="card-image">${card.image || '🔧'}</div>
                <div class="card-name">${card.name}</div>
            </div>
            <div class="card-description">${card.description || ''}</div>
            ${statsHtml}
            <div class="card-activations">${this.formatActivations(card.activations)}</div>
            <a href="/save_card/${card.uuid}" target="_blank" class="download-btn">⬇️</a>
        `;
        
        if (!isInDeck) {
            cardDiv.addEventListener('click', () => this.addCardToDeck(card));
        }
        
        return cardDiv;
    }

    updateDeckDisplay() {
        const deckGrid = document.getElementById('deck-grid');
        
        if (this.currentDeck.length === 0) {
            deckGrid.innerHTML = '<div class="placeholder">Add cards to your deck</div>';
            return;
        }
        
        deckGrid.innerHTML = '';
        
        this.currentDeck.forEach(cardUuid => {
            const card = this.findCardByUuid(cardUuid);
            if (card) {
                const deckCardElement = this.createDeckCardElement(card);
                deckGrid.appendChild(deckCardElement);
            }
        });
    }

    createDeckCardElement(card) {
        const cardDiv = document.createElement('div');
        cardDiv.className = 'deck-card';
        cardDiv.dataset.cardId = card.uuid;
        
        let statsText = '';
        
        if (card.consumes && card.consumes.type !== 'none') {
            const consumesIcon = this.formatResourceType(card.consumes.type);
            const consumesName = this.formatResourceName(card.consumes.type);
            statsText += `${card.consumes.value}<span class="resource-icon-tooltip" title="${consumesName}">${consumesIcon}</span>`;
        }
        
        if (card.consumes && card.consumes.type !== 'none' && card.produces && card.produces.type !== 'none') {
            statsText += ' → ';
        }
        
        if (card.produces && card.produces.type !== 'none') {
            const producesIcon = this.formatResourceType(card.produces.type);
            const producesName = this.formatResourceName(card.produces.type);
            statsText += `${card.produces.value}<span class="resource-icon-tooltip" title="${producesName}">${producesIcon}</span>`;
        }
        
        cardDiv.innerHTML = `
            <div class="deck-card-image">${card.image || '🔧'}</div>
            <div class="deck-card-info">
                <div class="deck-card-name">${card.name}</div>
                <div class="deck-card-stats">${statsText}</div>
            </div>
        `;
        
        cardDiv.addEventListener('click', () => this.removeCardFromDeck(card.uuid));
        
        return cardDiv;
    }

    addCardToDeck(card) {
        if (this.selectedCards.has(card.uuid)) {
            return; // Already in deck
        }
        
        this.currentDeck.push(card.uuid);
        this.selectedCards.add(card.uuid);
        
        this.updateUI();
        this.updateStatus(`Added "${card.name}" to deck`);
    }

    removeCardFromDeck(cardUuid) {
        const index = this.currentDeck.indexOf(cardUuid);
        if (index !== -1) {
            this.currentDeck.splice(index, 1);
            this.selectedCards.delete(cardUuid);
            
            const card = this.findCardByUuid(cardUuid);
            const cardName = card ? card.name : 'Card';
            
            this.updateUI();
            this.updateStatus(`Removed "${cardName}" from deck`);
        }
    }

    clearDeck() {
        if (this.currentDeck.length === 0) {
            return;
        }
        
        this.currentDeck = [];
        this.selectedCards.clear();
        
        this.updateUI();
        this.updateStatus('Deck cleared');
    }

    async submitDeck() {
        if (this.currentDeck.length === 0) {
            this.updateStatus('Cannot submit empty deck');
            return;
        }
        
        this.showLoading(true);
        this.updateStatus('Submitting deck...');
        this.clearError();
        
        try {
            let body = {
                card_ids: this.currentDeck,
            }
            const response = await fetch('/update_deck', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'session-id': this.sessionId.toString(),
                },
                body: JSON.stringify(body)
            });
            
            const result = await response.json();
            
            if (result.error) {
                this.showError(result.error);
                this.updateStatus('Failed to update deck');
                return;
            }
            
            if (!response.ok) {
                throw new Error('Failed to update deck');
            }
            
            this.updateStatus('Deck updated successfully!');
            
        } catch (error) {
            console.error('Error submitting deck:', error);
            this.updateStatus('Failed to submit deck');
            this.showError('Failed to submit deck: ' + error.message);
        } finally {
            this.showLoading(false);
        }
    }

    updateDeckStats() {
        const deckCountElement = document.getElementById('deck-count');
        if (deckCountElement) {
            deckCountElement.textContent = this.currentDeck.length;
        }
    }

    updateSubmitButton() {
        const submitButton = document.getElementById('submit-deck-btn');
        if (submitButton) {
            submitButton.disabled = this.currentDeck.length === 0;
        }
    }

    findCardByUuid(uuid) {
        return this.cardCollection.find(card => card.uuid === uuid);
    }

    formatResourceType(type) {
        return getResourceIcon(type, type);
    }

    formatResourceName(type) {
        // Capitalize first letter and handle any special formatting
        return type.charAt(0).toUpperCase() + type.slice(1);
    }

    formatActivations(activations) {
        if (activations === 0) {
            return '∞';
        }
        return activations.toString();
    }

    updateStatus(message) {
        const statusElement = document.getElementById('status-message');
        if (statusElement) {
            statusElement.textContent = message;
            
            // Add fade effect
            statusElement.style.opacity = '0.5';
            setTimeout(() => {
                statusElement.style.opacity = '1';
            }, 100);
        }
    }

    showLoading(show) {
        const loadingOverlay = document.getElementById('loading-overlay');
        if (loadingOverlay) {
            if (show) {
                loadingOverlay.classList.add('show');
            } else {
                loadingOverlay.classList.remove('show');
            }
        }
    }

    showError(message) {
        const errorContainer = document.getElementById('error-container');
        if (errorContainer) {
            const errorText = errorContainer.querySelector('.error-text');
            if (errorText) {
                errorText.textContent = message;
            }
            errorContainer.style.display = 'block';
        }
    }

    clearError() {
        const errorContainer = document.getElementById('error-container');
        if (errorContainer) {
            errorContainer.style.display = 'none';
        }
    }

    triggerFileUpload() {
        const fileInput = document.getElementById('card-file-input');
        fileInput.click();
    }

    async handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) {
            return;
        }

        this.showLoading(true);
        this.updateStatus(`Loading card from ${file.name}...`);
        this.clearError();

        try {
            // Read file contents as text
            const fileContents = await this.readFileAsText(file);
            
            // Post to /load_card endpoint
            const response = await fetch('/load_card', {
                method: 'POST',
                headers: {
                    'Content-Type': 'text/plain',
                    'session-id': this.sessionId.toString()
                },
                body: fileContents
            });

            const result = await response.json();

            if (result.error) {
                this.showError(result.error);
                this.updateStatus('Failed to load card');
                return;
            }

            if (!response.ok) {
                throw new Error('Failed to load card');
            }

            this.updateStatus(`Card loaded successfully from ${file.name}!`);
            
            // Reload card collection to show the new card
            await this.loadCardCollection();
            this.updateCardCollection();

        } catch (error) {
            console.error('Error uploading card:', error);
            this.updateStatus('Failed to load card');
            this.showError('Failed to load card: ' + error.message);
        } finally {
            this.showLoading(false);
            // Clear the file input so the same file can be uploaded again
            event.target.value = '';
        }
    }

    readFileAsText(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = (e) => resolve(e.target.result);
            reader.onerror = (e) => reject(new Error('Failed to read file'));
            reader.readAsText(file);
        });
    }
}

// Initialize the deck builder when the page loads
document.addEventListener('DOMContentLoaded', () => {
    window.deckBuilder = new DeckBuilder();
});