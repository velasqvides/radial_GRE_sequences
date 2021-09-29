% This Script gathers all the necessary information to create a 3D stack of
% stars sequence.
% Most of the inputs are validated in a first stage to check basic 
% consitency, then deeper validation is performed to see if the intended  
% resolution and contrast can be achieved. Messages are given in the 
% command window in case that some parameter is modified. 
%  
clear variables
%% I. data collection
% 1. Resolution
 
inputs.FOV = 256e-3;            % in meters
inputs.slabThickness = 256e-3;  % in meters
inputs.Nx = 256;  
inputs.Nz = 256;        
inputs.nSpokes = 256;                       
inputs.bandwidthPerPixel = 1628; % in Herz                  
inputs.readoutOversampling = 2;  % 1: no oversampling, 2: 2x oversampling  
% 2. Approach to steady state
inputs.nDummyScans = 335;
% 3. Spoling strategy 
inputs.phaseDispersionReadout = 2*pi;     % desired phase dispersion along readout;
inputs.phaseDispersionZ = 2*pi;           % desired phase dispersion along z;
inputs.GzSpoilerArea = 'adaptive';          % 'adaptive', 'constant'  
inputs.RfSpoilingIncrement = 117;           % in degrees
% 4. Angular ordering
inputs.angularOrdering = 'goldenAngle';     % 'uniform', 'uniformAlternating', 'goldeAngle'
inputs.goldenAngleSequence = 1;             % 1: goldeAngle, 2: smallGoldenAngle, >2: tinyGoldenAngles
inputs.angleRange = 'fullCircle';           % 'fullCircle' or 'halfCircle'
inputs.partitionRotation = 'goldenAngle';   % 'aligned', 'linear', 'goldenAngle'
inputs.viewOrder = 'partitionsInInnerLoop'; % 'partitionsInInnerLoop', 'partitionsInOuterLoop'
% 5. RF Excitation
inputs.RfExcitation = 'selectiveSinc';    % 'nonSelective', 'selectiveSinc'
inputs.RfPulseDuration = 400e-6;          % use 200e-6 for nonSelective, in seconds
inputs.RfPulseApodization = 0.5;          % 0: unapodized, 0.46: Haming, 0.5: Hanning
inputs.timeBWProduct = 2;                 % dimensionless
% 6. Main system limits
inputs.maxGradient = 50;                  % in mT/m
inputs.maxSlewRate = 150;                 % in T/m/s
% 7. Set more system limits, and group them into a structure variable
systemLimits = mr.opts('MaxGrad', inputs.maxGradient, 'GradUnit', 'mT/m', ...
    'MaxSlew', inputs.maxSlewRate, 'SlewUnit', 'T/m/s', ...
    'rfRingdownTime', 20e-6, 'rfDeadTime', 100e-6, ...
    'adcDeadTime', 20e-6);
% 8. Main operator-selectable parameters
inputs.TE = 2.21e-3;                             % in seconds
inputs.TR = 4.36e-3;                             % in seconds
inputs.flipAngle = 5;                     % in degrees

%% II. Check and save the input data.
% 1. First, check that all input values makes sense regarding to:
% data-type, format, range, cardinality, spelling and consistency.
validateInputs(inputs) % works only with versions R2019b and later.
% 2. Validate resolution.
[inputs.Nx, inputs.FOV, inputs.bandwidthPerPixel] = validateResolution(inputs.Nx,inputs.FOV,inputs.bandwidthPerPixel,systemLimits);
[inputs.Nz, inputs.slabThickness, inputs.RfPulseDuration, inputs.timeBWProduct ] = validateResolutionZ(inputs,systemLimits);
% 3. Validate TE and TR values.
[inputs.TE, inputs.TR ] = validateTEandTR(inputs, systemLimits); % further validation for TE and TR
% 4. Get feedback about the estimated number of dummy scans based on current
% TR, flip angle, and the next two parameters:
T1 = 1284e-3; % T1 for white matter at 7T
error = 0.10; % normalized error between longitudinal magnetization value and its steady-state value 
estimateNdummyScans(inputs.TR,inputs.flipAngle,T1,error,inputs.nDummyScans)
clear T1 error;
% 5. The two struct final variables will be saved into parameters.mat
% parameter.mat needs to be loaded into the main script to create the sequence
save('parametersSoS.mat','inputs','systemLimits');
