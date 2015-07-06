function [Y mask M] = stubI_messlMcIld(X, fail, fs, inFile, I, allPairs, d, useHardMask, varargin)

% Multichannel MESSL mask with simple beamforming initialized from ILD
% between reference file and mic2 or if mic2 has failed, then cross
% correlations between mics. 

if ~exist('I', 'var') || isempty(I), I = 1; end
if ~exist('allPairs', 'var') || isempty(allPairs), allPairs = true; end
if ~exist('d', 'var') || isempty(d), d = 0.35; end
if ~exist('useHardMask', 'var') || isempty(useHardMask), useHardMask = true; end

% Check that mrfHardCompatExp is not zero
ind = find(strcmp(varargin, 'mrfHardCompatExp'));
if useHardMask && (isempty(ind) || (varargin{ind+1} == 0))
    error('Must set "mrfHardCompatExp" to nonzero value with useHardMask')
end

refDir = '/data/corpora/chime3/CHiME3/data/audio/16kHz/enhancedLocal/beamformit_1s_sc_ch1_3-6/';

threshold_db = 6;
maxSup_db = -40;

maxSup = 10^(maxSup_db/20);
tau = tauGrid(d, fs, 31);
fprintf('Max ITD: %g samples\n', tau(end));

% Compute ILD initialization
refFile = fullfile(refDir, strrep(inFile, '.CH1', ''));
if ~fail(2) && exist(refFile, 'file')
    [mvdr fsm] = wavread(refFile);
    assert(fsm == fs);
    wlen = (size(X,1)-1)*2;
    M = stft_multi(mvdr.', wlen);

    % Compute ILD between MVDR output and mic 2 (rear-facing)
    maskInit = maxSup + (1-2*maxSup)*(db(M(2:end-1,:) ./ X(2:end-1,:,2)) > threshold_db);
    maskInit = cat(3, maskInit, 1 - maskInit);
else
    fprintf('\b NOT using ILD initialization\n');
    maskInit = [];
end

% Figure out which mic to use for reference
if allPairs
    refMic = 0;
else
    if ~fail(2)
        refMic = 2;
    else
        refMic = find(~fail, 1, 'first');
    end
    if isempty(refMic)
        error('All potential reference mics have failed')
    end
end


% MESSL for mask
messlOpts = [{'GarbageSrc', 1, 'fixIPriors', 1, 'maskInit', maskInit, 'refMic', refMic} varargin];
[p_lr_iwt params hardMasks] = messlMultichannel(X(2:end-1,:,~fail), tau, I, messlOpts{:});

if useHardMask
    mask = squeeze(hardMasks(1,:,:,1));
else
    mask = prob2mask(squeeze(p_lr_iwt(1,:,:,1)));
end

z = zeros([1 size(X,2) size(mask,3)]);
mask = cat(1, z, mask, z);
mask = maxSup + (1 - maxSup) * mask;

% Output spectrogram(s)
Y = M .* mask;
