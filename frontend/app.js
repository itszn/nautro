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

class NautroGame {
    constructor() {
        this.sessionId = null;
        this.gameState = null;
        this.selectedCards = []; // Changed to array to maintain order
        this.maxSelection = 5;
        this.resourceChanges = null; // Store resource changes after successful play
        this.cardActivationLimits = {}; // Track activation limits per card
        this.gameStarted = false; // Track if game has actually started
        
        this.extractSessionFromUrl();
        this.initializeEventListeners();
        this.updateUI();
        
        // If we have a session ID from URL, load the game state
        if (this.sessionId) {
            this.loadGameState();
        }
    }

    extractSessionFromUrl() {
        // Extract session ID from URL hash (e.g., #session_id=12345)
        const hash = window.location.hash.substring(1); // Remove the '#'
        if (hash) {
            const hashParams = new URLSearchParams(hash);
            const sessionFromUrl = hashParams.get('session_id');
            if (sessionFromUrl) {
                this.sessionId = sessionFromUrl;
                // Clear the hash to clean up the URL after extracting the session
                window.history.replaceState(null, null, window.location.pathname);
            }
        }
    }

    initializeEventListeners() {
        document.getElementById('new-game-btn').addEventListener('click', () => this.startNewGame());
        document.getElementById('deck-builder-btn').addEventListener('click', () => this.openDeckBuilder());
        document.getElementById('submit-hand-btn').addEventListener('click', () => this.submitSelectedCards());
        document.getElementById('discard-cards-btn').addEventListener('click', () => this.discardSelectedCards());
    }

    async startNewGame() {
        this.showLoading(true);
        this.updateStatus('Starting new game...');
        
        // Clear previous game state
        this.selectedCards = [];
        this.resourceChanges = null;
        this.cardActivationLimits = {};
        this.gameStarted = false;
        this.clearError();

        try {
            const response = await fetch(`/new_game/`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' }
            });
            
            if (!response.ok) throw new Error('Failed to start new game');
            
            const data = await response.json();
            this.sessionId = data.uuid;
            
            this.updateStatus('Game created! You can edit your deck before starting. Click "Continue Playing" to begin!');
            this.updateUI(); // Update UI to show pre-start state
            
        } catch (error) {
            console.error('Error starting new game:', error);
            this.updateStatus('Failed to start new game. Please try again.');
        } finally {
            this.showLoading(false);
        }
    }

    async continueGame() {
        if (!this.sessionId) {
            this.updateStatus('No active game session. Please start a new game first.');
            return;
        }

        this.showLoading(true);
        this.updateStatus('Continuing game...');
        this.clearError();
        
        try {
            const response = await fetch('/continue', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'session-id': this.sessionId.toString()
                }
            });
            
            if (!response.ok) throw new Error('Failed to continue game');
            
            this.gameStarted = true; // Mark game as started
            // Clear resource changes and epoch change to prevent the box from showing again
            this.resourceChanges = null;
            this.epochChange = null;
            await this.loadGameState();
            this.updateStatus('Game continued! Ready to play!');
            
        } catch (error) {
            console.error('Error continuing game:', error);
            this.updateStatus('Failed to continue game. Please try again.');
        } finally {
            this.showLoading(false);
        }
    }

    async loadGameState() {
        if (!this.sessionId) return;
        
        try {
            const response = await fetch('/game_state', {
                headers: { 'session-id': this.sessionId.toString() }
            });
            
            if (!response.ok) {
                // If session doesn't exist, just ignore it and reset to main menu
                this.sessionId = null;
                this.gameState = null;
                this.gameStarted = false;
                this.updateUI();
                this.updateStatus('Welcome to Nautro! Start a new game to begin your survival journey.');
                return;
            }
            
            this.gameState = await response.json();
            
            // If game has been started via /continue, mark it as started
            if (this.gameState && this.gameState.hand && this.gameState.hand.length > 0) {
                this.gameStarted = true;
            }
            
            this.updateUI();
            
            if (this.gameStarted) {
                this.updateStatus('Game resumed! Ready to play! Select up to 5 cards and submit your hand.');
            }
            
        } catch (error) {
            console.warn('Could not load game state, resetting to main menu:', error);
            // Reset to main menu state if there's any error
            this.sessionId = null;
            this.gameState = null;
            this.gameStarted = false;
            this.updateUI();
            this.updateStatus('Welcome to Nautro! Start a new game to begin your survival journey.');
        }
    }

    async submitSelectedCards() {
        if (this.selectedCards.length === 0) {
            this.updateStatus('Please select at least one card to play.');
            return;
        }

        this.showLoading(true);
        this.updateStatus('Playing selected cards...');
        this.clearError();
        
        // Store previous resource state and epoch for comparison
        const previousResources = this.gameState ? this.cloneResources(this.gameState.resources) : {};
        const previousEpoch = this.gameState ? this.gameState.epoch : 0;
        
        try {
            const response = await fetch('/play_cards', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'session-id': this.sessionId.toString(),
                    'x-sign': true
                },
                body: JSON.stringify({ card_ids: this.selectedCards.map(cardId => {
                    const limit = this.cardActivationLimits[cardId];
                    if (limit !== undefined) {
                        // Pack activation count and card ID: (activations << 32) | cardId
                        // Use BigInt for proper 64-bit arithmetic
                        return Number((BigInt(limit) << 32n) | BigInt(cardId));
                    }
                    return cardId;
                }) })
            });
            
            const result = await response.json();
            
            // Check if response contains an error message
            if (result.error) {
                this.displayError(result.error);
                this.updateStatus('Request failed. Please check the error message below.');
                return;
            }
            
            if (!response.ok) throw new Error('Failed to play cards');
            
            if (result.success) {
                this.selectedCards = [];
                this.clearError();
                await this.loadGameState();
                
                // Calculate and display resource and epoch changes
                this.resourceChanges = this.calculateResourceChanges(previousResources, this.gameState.resources);
                this.epochChange = this.calculateEpochChange(previousEpoch, this.gameState.epoch);
                this.updatePlayArea();
                this.updateHand(); // Update hand again to show epoch message if needed
                this.updateStatus('Cards played successfully!');
            } else {
                this.displayError(result.failed_reason || 'Unknown error occurred', result.failed_on);
                this.highlightFailedCard(result.failed_on);
                this.updateStatus('Card selection failed. Please check the error message below.');
            }
            
        } catch (error) {
            console.error('Error playing cards:', error);
            this.updateStatus('Failed to play cards. Please try again.');
        } finally {
            this.showLoading(false);
        }
    }

    async discardSelectedCards() {
        if (this.selectedCards.length === 0) {
            this.updateStatus('Please select at least one card to discard.');
            return;
        }

        this.showLoading(true);
        this.updateStatus('Discarding selected cards...');
        this.clearError();
        
        try {
            const response = await fetch('/discard_cards', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'session-id': this.sessionId.toString()
                },
                body: JSON.stringify({ card_ids: this.selectedCards })
            });
            
            const result = await response.json();
            
            // Check if response contains an error message
            if (result.error) {
                this.displayError(result.error);
                this.updateStatus('Discard failed. Please check the error message below.');
                return;
            }
            
            if (!response.ok) throw new Error('Failed to discard cards');
            
            // Clear selection and refresh game state
            this.selectedCards = [];
            this.cardActivationLimits = {};
            this.clearError();
            await this.loadGameState();
            this.updateStatus('Cards discarded successfully!');
            
        } catch (error) {
            console.error('Error discarding cards:', error);
            this.updateStatus('Failed to discard cards. Please try again.');
        } finally {
            this.showLoading(false);
        }
    }

    updateUI() {
        this.updateResources();
        this.updateEpochInfo();
        this.updateHand();
        this.updatePlayArea();
        this.updateSelectionCounter();
        this.updateSubmitButton();
    }

    updateResources() {
        const resourcesContainer = document.getElementById('resources-container');
        if (!resourcesContainer) return;

        // Clear existing resources
        resourcesContainer.innerHTML = '';

        if (!this.gameState || !this.gameState.resources) {
            // Show default energy resource
            this.createResourceElement('energy', 1, resourcesContainer);
            return;
        }

        // Create resource elements dynamically based on server response
        // Only show resources > 0 (except energy which always shows)
        this.gameState.resources.forEach(resource => {
            if (resource.value > 0 || resource.type === 'energy') {
                this.createResourceElement(resource.type, resource.value, resourcesContainer);
            }
        });
    }

    createResourceElement(type, value, container) {
        const resourceDiv = document.createElement('div');
        resourceDiv.className = `resource-item ${type}`;
        
        const icon = this.getResourceIcon(type);
        const displayName = this.formatResourceName(type);
        
        resourceDiv.innerHTML = `
            <div class="resource-icon" title="${displayName}">${icon}</div>
            <div class="resource-info">
                <span class="resource-name">${displayName}</span>
                <span class="resource-value" id="${type}-value">${value}</span>
            </div>
        `;
        
        container.appendChild(resourceDiv);
        
        // Add animation effect
        setTimeout(() => {
            const valueElement = resourceDiv.querySelector('.resource-value');
            if (valueElement) {
                valueElement.style.transform = 'scale(1.2)';
                valueElement.style.transition = 'transform 0.3s ease';
                setTimeout(() => {
                    valueElement.style.transform = 'scale(1)';
                }, 300);
            }
        }, 50);
    }

    getResourceIcon(type) {
        return getResourceIcon(type);
    }

    formatResourceName(type) {
        // Capitalize first letter and handle any special formatting
        return type.charAt(0).toUpperCase() + type.slice(1);
    }

    updateEpochInfo() {
        if (!this.gameState) return;
        
        const epochElement = document.getElementById('epoch');
        const escapeElement = document.getElementById('escape-target');
        const setsLeftElement = document.getElementById('sets-left');
        const discardsLeftElement = document.getElementById('discards-left');
        const setSizeElement = document.getElementById('set-size');
        const deckSizeElement = document.getElementById('deck-size');
        
        if (epochElement) epochElement.textContent = this.gameState.epoch !== undefined ? this.gameState.epoch : '-';
        if (escapeElement) escapeElement.textContent = this.gameState.escape !== undefined ? this.gameState.escape : '-';
        if (setsLeftElement) setsLeftElement.textContent = this.gameState.sets_left !== undefined ? this.gameState.sets_left : '-';
        if (discardsLeftElement) discardsLeftElement.textContent = this.gameState.discards_left !== undefined ? this.gameState.discards_left : '-';
        if (setSizeElement) setSizeElement.textContent = this.gameState.set_size !== undefined ? this.gameState.set_size : '-';
        if (deckSizeElement) deckSizeElement.textContent = this.gameState.deck_size !== undefined ? this.gameState.deck_size : '-';
        
        // Handle pulsing red effect and game over
        this.handleSetsLeftEffects();
    }

    handleSetsLeftEffects() {
        if (!this.gameState) return;
        
        const setsLeftElement = document.getElementById('sets-left');
        const playArea = document.getElementById('play-area');
        
        if (this.gameState.sets_left === 0) {
            // Game over - display in play area
            if (playArea) {
                playArea.innerHTML = `
                    <div class="game-over-message">
                        <h2>GAME OVER</h2>
                        <p>You have no sets left!</p>
                    </div>
                `;
            }
            // Remove pulsing effect
            if (setsLeftElement) {
                setsLeftElement.classList.remove('pulsing-red');
            }
        } else if (this.gameState.sets_left === 1) {
            // Add pulsing red effect
            if (setsLeftElement) {
                setsLeftElement.classList.add('pulsing-red');
            }
        } else {
            // Remove pulsing red effect
            if (setsLeftElement) {
                setsLeftElement.classList.remove('pulsing-red');
            }
        }
    }

    updateHand() {
        const handElement = document.getElementById('card-hand');
        
        // Check if epoch has advanced and show deck modification reminder FIRST
        if (this.epochChange) {
            handElement.innerHTML = `
                <div class="hand-placeholder">
                    <div style="font-size: 1rem; color: rgba(255, 255, 255, 0.8); font-style: italic;">
                        💡 Perfect time to modify your deck! Click "Deck Builder" or "Continue Playing" to proceed.
                    </div>
                </div>
            `;
            return;
        }
        
        if (!this.gameState || !this.gameState.hand || !this.gameStarted) {
            if (this.sessionId && !this.gameStarted) {
                handElement.innerHTML = '<div class="hand-placeholder">Game created! You can edit your deck or click "Continue Playing" to start.</div>';
            } else {
                handElement.innerHTML = '<div class="hand-placeholder">No cards available. Start a new game to load your hand.</div>';
            }
            return;
        }
        
        handElement.innerHTML = '';
        
        this.gameState.hand.forEach(card => {
            const cardElement = this.createCardElement(card);
            handElement.appendChild(cardElement);
        });
    }


    createCardElement(card, isInPlayArea = false) {
        const cardDiv = document.createElement('div');
        cardDiv.className = 'card';
        cardDiv.dataset.cardId = card.uuid;
        
        if (this.selectedCards.includes(card.uuid)) {
            cardDiv.classList.add('selected');
        }
        
        if (isInPlayArea) {
            // Compact version for play area
            let statsHtml = '<div class="card-stats-compact">';
            
            // Only show consumes if not "none"
            if (card.consumes.type !== 'none') {
                const consumesIcon = this.formatResourceType(card.consumes.type);
                const consumesName = this.formatResourceName(card.consumes.type);
                statsHtml += `<span class="stat-value consumes">${card.consumes.value}<span class="resource-icon-tooltip" title="${consumesName}">${consumesIcon}</span></span>`;
            }
            
            // Only show arrow and produces if both exist and produces is not "none"
            if (card.consumes.type !== 'none' && card.produces.type !== 'none') {
                statsHtml += `<span class="arrow">→</span>`;
            }
            
            // Only show produces if not "none"
            if (card.produces.type !== 'none') {
                const producesIcon = this.formatResourceType(card.produces.type);
                const producesName = this.formatResourceName(card.produces.type);
                statsHtml += `<span class="stat-value produces">${card.produces.value}<span class="resource-icon-tooltip" title="${producesName}">${producesIcon}</span></span>`;
            }
            
            statsHtml += '</div>';
            
            cardDiv.innerHTML = `
                <div class="card-header">
                    <div class="card-image">${card.image || '🔧'}</div>
                    <div class="card-name">${card.name}</div>
                </div>
                ${statsHtml}
                <div class="card-activations clickable" data-card-id="${card.uuid}">${this.formatActivationsForPlayArea(card)}</div>
            `;
            
            const playOrder = this.selectedCards.indexOf(card.uuid) + 1;
            const orderDiv = document.createElement('div');
            orderDiv.className = 'play-order';
            orderDiv.textContent = playOrder;
            cardDiv.appendChild(orderDiv);
            
            cardDiv.addEventListener('click', () => this.removeFromPlayArea(card.uuid));
            
            // Add click handler for activation limit in play area
            const activationElement = cardDiv.querySelector('.card-activations.clickable');
            if (activationElement) {
                activationElement.addEventListener('click', (e) => this.handleActivationClick(card.uuid, e));
            }
        } else {
            // Full version for hand
            let statsHtml = '<div class="card-stats">';
            
            // Only show consumes if not "none"
            if (card.consumes.type !== 'none') {
                const consumesIcon = this.formatResourceType(card.consumes.type);
                const consumesName = this.formatResourceName(card.consumes.type);
                statsHtml += `
                    <div class="card-stat">
                        <span class="stat-label">Consumes:</span>
                        <span class="stat-value consumes">${card.consumes.value} <span class="resource-icon-tooltip" title="${consumesName}">${consumesIcon}</span></span>
                    </div>`;
            }
            
            // Only show produces if not "none"
            if (card.produces.type !== 'none') {
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
                <div class="card-description">${card.description}</div>
                ${statsHtml}
                <div class="card-activations">${this.formatActivations(card.activations)}</div>
            `;
            
            cardDiv.addEventListener('click', () => this.toggleCardSelection(card.uuid, cardDiv));
        }
        
        return cardDiv;
    }

    formatResourceType(type) {
        return getResourceIcon(type, type);
    }

    formatActivations(activations) {
        if (activations === 0) {
            return '∞';
        }
        return activations.toString();
    }

    formatActivationsForPlayArea(card) {
        const maxActivations = card.activations;
        const currentLimit = this.cardActivationLimits[card.uuid];
        
        if (maxActivations === 0) {
            // For infinite activations, show limit if set, otherwise show ∞
            if (currentLimit !== undefined) {
                if (currentLimit === 0) {
                    return '∞';
                }
                return `${currentLimit}/∞`;
            }
            return '∞';
        }
        
        // For finite activations, show n/m format unless n==m, then just show n
        const effectiveLimit = currentLimit !== undefined ? currentLimit : maxActivations;
        if (effectiveLimit === maxActivations) {
            return maxActivations.toString();
        }
        return `${effectiveLimit}/${maxActivations}`;
    }

    handleActivationClick(cardId, event) {
        event.stopPropagation();
        
        const card = this.findCardById(cardId);
        if (!card) {
            return;
        }
        
        const currentLimit = this.cardActivationLimits[cardId];
        let promptMessage, defaultValue;
        
        if (card.activations === 0) {
            promptMessage = `Enter number of activations for ${card.name} (infinite card, enter 0 for infinite):`;
            defaultValue = currentLimit !== undefined ? currentLimit.toString() : '0';
        } else {
            promptMessage = `Enter number of activations for ${card.name} (1-${card.activations}):`;
            defaultValue = currentLimit !== undefined ? currentLimit.toString() : card.activations.toString();
        }
        
        const userInput = prompt(promptMessage, defaultValue);
        
        if (userInput === null) {
            return; // User cancelled
        }
        
        const newLimit = parseInt(userInput);
        
        if (isNaN(newLimit) || newLimit < 0) {
            alert('Please enter a valid number (0 or greater)');
            return;
        }
        
        if (card.activations !== 0 && (newLimit < 1 || newLimit > card.activations)) {
            alert(`Please enter a valid number between 1 and ${card.activations}`);
            return;
        }
        
        if (newLimit === 0 && card.activations === 0) {
            // User wants infinite activations, remove the limit
            delete this.cardActivationLimits[cardId];
        } else {
            this.cardActivationLimits[cardId] = newLimit;
        }
        
        this.updatePlayArea();
    }

    toggleCardSelection(cardId, cardElement) {
        const cardIndex = this.selectedCards.indexOf(cardId);
        
        // Clear resource changes when starting a new selection
        if (this.resourceChanges) {
            this.resourceChanges = null;
            this.epochChange = null;
        }
        
        if (cardIndex !== -1) {
            // Card is selected, remove it
            this.selectedCards.splice(cardIndex, 1);
            cardElement.classList.remove('selected');
            // Remove activation limit when card is deselected
            delete this.cardActivationLimits[cardId];
        } else {
            // Card is not selected, add it
            const maxSelection = this.gameState && this.gameState.set_size !== undefined ? this.gameState.set_size : this.maxSelection;
            if (this.selectedCards.length >= maxSelection) {
                this.updateStatus(`You can only select up to ${maxSelection} cards at a time.`);
                return;
            }
            this.selectedCards.push(cardId);
            cardElement.classList.add('selected');
        }
        
        this.updatePlayArea();
        this.updateSelectionCounter();
        this.updateSubmitButton();
    }

    removeFromPlayArea(cardId) {
        const cardIndex = this.selectedCards.indexOf(cardId);
        if (cardIndex !== -1) {
            this.selectedCards.splice(cardIndex, 1);
            // Remove activation limit when card is removed from play area
            delete this.cardActivationLimits[cardId];
            this.updateHand();
            this.updatePlayArea();
            this.updateSelectionCounter();
            this.updateSubmitButton();
        }
    }

    updatePlayArea() {
        const playArea = document.getElementById('play-area');
        if (!playArea) return;

        // Don't clear play area if it's showing game over
        if (this.gameState && this.gameState.sets_left === 0) {
            return; // Game over message should persist
        }

        playArea.innerHTML = '';

        // Show continue button if game is created but not started
        if (this.sessionId && !this.gameStarted) {
            const continueContainer = document.createElement('div');
            continueContainer.className = 'resource-changes-container';
            
            const title = document.createElement('div');
            title.className = 'resource-changes-title';
            title.textContent = 'Ready to Start?';
            
            const message = document.createElement('div');
            message.className = 'continue-message';
            message.textContent = 'You can edit your deck or start your survival journey!';
            message.style.cssText = 'text-align: center; margin: 10px 0; font-size: 1.1rem; color: rgba(255, 255, 255, 0.9);';
            
            const continueButton = document.createElement('button');
            continueButton.className = 'clear-changes-btn';
            continueButton.textContent = 'Ready To Go!';
            continueButton.addEventListener('click', () => this.continueGame());
            
            continueContainer.appendChild(title);
            continueContainer.appendChild(message);
            continueContainer.appendChild(continueButton);
            playArea.appendChild(continueContainer);
            return;
        }

        // Show resource changes if available (after successful play)
        if ((this.resourceChanges && Object.keys(this.resourceChanges).length > 0) || this.epochChange) {
            this.displayResourceChanges(playArea);
            return;
        }

        if (this.selectedCards.length === 0) {
            const placeholder = document.createElement('div');
            placeholder.className = 'play-area-placeholder';
            placeholder.textContent = 'Select cards from your hand to play them in order';
            playArea.appendChild(placeholder);
            return;
        }

        // Find the cards data and create elements in play area
        this.selectedCards.forEach(cardId => {
            const card = this.findCardById(cardId);
            if (card) {
                const cardElement = this.createCardElement(card, true);
                playArea.appendChild(cardElement);
            }
        });
    }

    findCardById(cardId) {
        if (this.gameState && this.gameState.hand) {
            return this.gameState.hand.find(card => card.uuid === cardId);
        }
        
        return null;
    }

    updateSelectionCounter() {
        const counterElement = document.getElementById('selected-count');
        const maxSelectionElement = document.getElementById('max-selection');
        
        if (counterElement) {
            counterElement.textContent = this.selectedCards.length;
        }
        
        if (maxSelectionElement) {
            const maxSelection = this.gameState && this.gameState.set_size !== undefined ? this.gameState.set_size : this.maxSelection;
            maxSelectionElement.textContent = maxSelection;
        }
    }

    updateSubmitButton() {
        const submitButton = document.getElementById('submit-hand-btn');
        const discardButton = document.getElementById('discard-cards-btn');
        const deckBuilderButton = document.getElementById('deck-builder-btn');
        
        const hasSelection = this.selectedCards.length > 0;
        const hasDiscards = this.gameState && this.gameState.discards_left !== undefined && this.gameState.discards_left > 0;
        const hasSession = this.sessionId !== null;
        
        if (submitButton) {
            submitButton.disabled = !hasSelection;
        }
        
        if (discardButton) {
            discardButton.disabled = !hasSelection || !hasDiscards;
        }
        
        if (deckBuilderButton) {
            deckBuilderButton.disabled = !hasSession;
        }
    }

    openDeckBuilder() {
        if (!this.sessionId) {
            this.updateStatus('Please start a new game first to access the deck builder.');
            return;
        }
        
        // Open deck builder in same window with session ID as hash parameter
        window.location.href = `deck_builder#session_id=${this.sessionId}`;
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

    displayError(message, failedCardIndex) {
        let errorContainer = document.getElementById('error-container');
        if (!errorContainer) {
            errorContainer = document.createElement('div');
            errorContainer.id = 'error-container';
            errorContainer.className = 'error-message';
            
            const playArea = document.getElementById('play-area');
            if (playArea && playArea.parentNode) {
                playArea.parentNode.insertBefore(errorContainer, playArea.nextSibling);
            }
        }
        
        let errorText = message;
        if (failedCardIndex !== undefined) {
            const failedCard = this.findCardByIndex(failedCardIndex);
            if (failedCard) {
                errorText += ` (Failed on card: ${failedCard.name})`;
            }
        }
        
        errorContainer.innerHTML = `
            <div class="error-icon">⚠️</div>
            <div class="error-text">${errorText}</div>
        `;
        errorContainer.style.display = 'block';
    }

    clearError() {
        const errorContainer = document.getElementById('error-container');
        if (errorContainer) {
            errorContainer.style.display = 'none';
        }
        this.clearCardHighlights();
    }

    highlightFailedCard(failedCardIndex) {
        this.clearCardHighlights();
        
        if (failedCardIndex !== undefined && failedCardIndex < this.selectedCards.length) {
            const playArea = document.getElementById('play-area');
            if (playArea) {
                const cardElements = playArea.querySelectorAll('.card');
                if (cardElements[failedCardIndex]) {
                    cardElements[failedCardIndex].classList.add('failed');
                }
            }
        }
    }

    clearCardHighlights() {
        const playArea = document.getElementById('play-area');
        if (playArea) {
            const cardElements = playArea.querySelectorAll('.card.failed');
            cardElements.forEach(card => card.classList.remove('failed'));
        }
    }

    findCardByIndex(index) {
        if (index >= 0 && index < this.selectedCards.length) {
            const cardId = this.selectedCards[index];
            return this.findCardById(cardId);
        }
        return null;
    }

    cloneResources(resources) {
        const resourceMap = {};
        if (resources) {
            resources.forEach(resource => {
                resourceMap[resource.type] = resource.value;
            });
        }
        return resourceMap;
    }

    calculateResourceChanges(previousResources, currentResources) {
        const changes = {};
        
        // Check current resources for changes
        if (currentResources) {
            currentResources.forEach(resource => {
                const previousValue = previousResources[resource.type] || 0;
                const currentValue = resource.value;
                const change = currentValue - previousValue;
                
                if (change !== 0) {
                    changes[resource.type] = {
                        change: change,
                        previousValue: previousValue,
                        currentValue: currentValue
                    };
                }
            });
        }
        
        // Check for resources that were in previous but not in current (went to 0)
        Object.keys(previousResources).forEach(resourceType => {
            if (!currentResources || !currentResources.find(r => r.type === resourceType)) {
                const previousValue = previousResources[resourceType];
                if (previousValue > 0) {
                    changes[resourceType] = {
                        change: -previousValue,
                        previousValue: previousValue,
                        currentValue: 0
                    };
                }
            }
        });
        
        return changes;
    }

    calculateEpochChange(previousEpoch, currentEpoch) {
        if (currentEpoch > previousEpoch) {
            return {
                previousEpoch: previousEpoch,
                currentEpoch: currentEpoch,
                increased: true
            };
        }
        return null;
    }

    displayResourceChanges(playArea) {
        const changesContainer = document.createElement('div');
        changesContainer.className = 'resource-changes-container';
        
        const title = document.createElement('div');
        title.className = 'resource-changes-title';
        title.textContent = 'Turn Results';
        changesContainer.appendChild(title);
        
        const changesGrid = document.createElement('div');
        changesGrid.className = 'resource-changes-grid';
        
        // Show epoch change if it occurred
        if (this.epochChange) {
            const epochElement = this.createEpochChangeElement(this.epochChange);
            changesGrid.appendChild(epochElement);
        }
        
        // Show resource changes if any
        if (this.resourceChanges) {
            Object.keys(this.resourceChanges).forEach(resourceType => {
                const changeData = this.resourceChanges[resourceType];
                const changeElement = this.createResourceChangeElement(resourceType, changeData);
                changesGrid.appendChild(changeElement);
            });
        }
        
        changesContainer.appendChild(changesGrid);
        
        const clearButton = document.createElement('button');
        clearButton.className = 'clear-changes-btn';
        clearButton.textContent = 'Continue Playing';
        clearButton.addEventListener('click', () => {
            // If epoch changed, call /continue endpoint to reset deck and shuffle
            if (this.epochChange) {
                this.continueGame();
            } else {
                // Just clear the display if no epoch change
                this.resourceChanges = null;
                this.epochChange = null;
                this.updatePlayArea();
            }
        });
        changesContainer.appendChild(clearButton);
        
        playArea.appendChild(changesContainer);
    }

    createEpochChangeElement(epochData) {
        const element = document.createElement('div');
        element.className = 'epoch-change-item';
        
        element.innerHTML = `
            <div class="epoch-change-icon">🌟</div>
            <div class="epoch-change-info">
                <div class="epoch-change-name">Epoch Advanced!</div>
                <div class="epoch-change-values">
                    <span class="previous-value">${epochData.previousEpoch}</span>
                    <span class="change-arrow">→</span>
                    <span class="current-value">${epochData.currentEpoch}</span>
                </div>
                <div class="epoch-change-delta positive">New Epoch!</div>
            </div>
        `;
        
        return element;
    }

    createResourceChangeElement(resourceType, changeData) {
        const element = document.createElement('div');
        element.className = 'resource-change-item';
        
        const icon = this.getResourceIcon(resourceType);
        const name = this.formatResourceName(resourceType);
        const change = changeData.change;
        const changeClass = change > 0 ? 'positive' : 'negative';
        const changeSign = change > 0 ? '+' : '';
        
        element.innerHTML = `
            <div class="resource-change-icon" title="${name}">${icon}</div>
            <div class="resource-change-info">
                <div class="resource-change-name">${name}</div>
                <div class="resource-change-values">
                    <span class="previous-value">${changeData.previousValue}</span>
                    <span class="change-arrow">→</span>
                    <span class="current-value">${changeData.currentValue}</span>
                </div>
                <div class="resource-change-delta ${changeClass}">${changeSign}${change}</div>
            </div>
        `;
        
        return element;
    }

    // Auto-refresh game state periodically
    startGameStatePolling() {
        if (this.pollingInterval) clearInterval(this.pollingInterval);
        
        this.pollingInterval = setInterval(() => {
            if (this.sessionId) {
                this.loadGameState();
            }
        }, 5000); // Poll every 5 seconds
    }

    stopGameStatePolling() {
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
    }
}

// Initialize the game when the page loads
document.addEventListener('DOMContentLoaded', () => {
    window.game = new NautroGame();
    
    // Add some visual flair
    document.body.addEventListener('click', (e) => {
        createClickEffect(e.clientX, e.clientY);
    });
});

// Create a sparkle effect on clicks
function createClickEffect(x, y) {
    const effect = document.createElement('div');
    effect.style.position = 'fixed';
    effect.style.left = x + 'px';
    effect.style.top = y + 'px';
    effect.style.width = '6px';
    effect.style.height = '6px';
    effect.style.background = '#26d0ce';
    effect.style.borderRadius = '50%';
    effect.style.pointerEvents = 'none';
    effect.style.zIndex = '9999';
    effect.style.boxShadow = '0 0 10px #26d0ce';
    
    document.body.appendChild(effect);
    
    const animation = effect.animate([
        { transform: 'scale(1)', opacity: 1 },
        { transform: 'scale(3)', opacity: 0 }
    ], {
        duration: 600,
        easing: 'ease-out'
    });
    
    animation.onfinish = () => effect.remove();
}
