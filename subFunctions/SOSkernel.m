classdef SOSkernel < kernel
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        Property1
    end
    
    methods
        function GzPartitionMax = createGzPartitionMax(obj)
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            deltaKz = obj.protocol.deltaKz;
            
            GzPartitionArea = (-nPartitions/2) * deltaKz; % Max area
            % get a dummy gradient with the maximum area of all GzPartitions
            GzPartitionMax = mr.makeTrapezoid('z',systemLimits,'Area',GzPartitionArea);
        end
        
        function GzPartitionsCell = createAllGzPartitions(obj)
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            deltaKz = obj.protocol.deltaKz;
            GzPartitionMax = createGzPartitionMax(obj);
            
            GzPartitionAreas = ((0:nPartitions-1) - nPartitions/2) * deltaKz; % areas go from bottom to top
            fixedGradientDuration = mr.calcDuration(GzPartitionMax);
            
            % make partition encoding gradients
            GzPartitionsCell = cell(1,nPartitions);
            for iz = 1:nPartitions
                GzPartitionsCell{iz} = mr.makeTrapezoid('z',systemLimits,'Area',GzPartitionAreas(iz),'Duration',fixedGradientDuration);
            end
            
        end
        
        function GzRephPlusPartitionsCell = createGzRephPlusPartitions(obj)
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            deltaKz = obj.protocol.deltaKz;
            [~, ~, GzReph] = obj.createSlabSelectionEvents;
            if isempty(GzReph)
                GzRephArea = 0;
            else
                GzRephArea = GzReph.area;
            end
            
            GzPartitionAreas = ((0:nPartitions-1) - nPartitions/2) * deltaKz; % areas go from bottom to top
            % get a dummy gradient with the maximum area of all GzPartitions
            dummyGradient = mr.makeTrapezoid('z',systemLimits,'Area',max(abs(GzPartitionAreas)) + abs(GzRephArea));
            % Use the duration of the dummy gradient for all the GzPartitions to keep
            % the TE and TR constant.
            fixedGradientDuration = mr.calcDuration(dummyGradient);
            
            GzRephPlusPartitionsCell = cell(1,nPartitions);
            for iz = 1:nPartitions
                % here, the area of the slab-rephasing lobe and partition-encoding lobes are added together
                GzRephPlusPartitionsCell{iz} = mr.makeTrapezoid('z',systemLimits,'Area',GzPartitionAreas(iz) + GzRephArea,...
                    'Duration',fixedGradientDuration);
            end
            
        end
        
        function GzCombinedCell = combineGzWithGzRephPlusPartitions(obj)
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            [~, Gz, ~] = createSlabSelectionEvents(obj);
            GzRephPlusPartitionsCell = createGzRephPlusPartitions(obj);
            
            GzCombinedCell = cell(1,nPartitions);
            for iz=1:nPartitions
                if isempty(Gz)% means that only GzPartition exist
                    GzCombinedCell{iz} = GzRephPlusPartitionsCell{iz};
                else
                    GzRephPlusPartitionsCell{iz}.delay = GzRephPlusPartitionsCell{iz}.delay + mr.calcDuration(Gz);
                    GzCombinedCell{iz} = mr.addGradients({Gz, GzRephPlusPartitionsCell{iz}}, 'system', systemLimits);
                end
            end
        end
        
        function [GzSpoilersCell, dispersionsPerTR] = createGzSpoilers(obj)
            
            phaseDispersionZ = obj.protocol.phaseDispersionZ;
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            partitionThickness = obj.protocol.partitionThickness;
            
            GzPartitionsCell = createAllGzPartitions(obj);
            GzPartitionMax = createGzPartitionMax(obj);
            dispersionDueToGzPartitionMax = obj.calculatePhaseDispersion(abs(GzPartitionMax.area), partitionThickness);
            
            GzSpoilersCell = cell(1,nPartitions);
            dispersionsPerTR = zeros(1,nPartitions);
            
            if phaseDispersionZ == 0 % just refocuse the phase encoding gradient in Z direction
                duration = mr.calcDuration(GzPartitionMax);
                for iz = 1:nPartitions
                    GzSpoilersCell{iz} = mr.makeTrapezoid('z',systemLimits,'Area',-GzPartitionsCell{iz}.area,'Duration',duration);
                    areaTotal = GzPartitionsCell{iz}.area + GzSpoilersCell{iz}.area;
                    dispersionsPerTR(iz) = obj.calculatePhaseDispersion(areaTotal, partitionThickness);
                end
                
            elseif phaseDispersionZ >= dispersionDueToGzPartitionMax
                % use the same duration to keep same TR
                AreaSpoilingZ_max = phaseDispersionZ / (2 * pi * partitionThickness);
                dummyGradient = mr.makeTrapezoid('z',systemLimits,'Area',abs(AreaSpoilingZ_max));
                fixedDurationGradient = mr.calcDuration(dummyGradient);
                for iZ=1:nPartitions
                    % GzPartition already add some phase dispersion to the spins
                    dispersionDueToThisPartition = obj.calculatePhaseDispersion(abs(GzPartitionsCell{iZ}.area), partitionThickness);
                    % Then we calculate the phase dispersion needed to get phaseDispersionZ in total
                    dispersionNeededZ = abs(phaseDispersionZ - dispersionDueToThisPartition);
                    AreaSpoilingNeededZ = dispersionNeededZ / (2 * pi * partitionThickness);
                    if GzPartitionsCell{iZ}.area < 0
                        GzSpoilersCell{iZ} = mr.makeTrapezoid('z','Area',-AreaSpoilingNeededZ,'Duration',fixedDurationGradient,'system',systemLimits);
                    else
                        GzSpoilersCell{iZ} = mr.makeTrapezoid('z','Area',AreaSpoilingNeededZ,'Duration',fixedDurationGradient,'system',systemLimits);
                    end
                    areaTotal = GzPartitionsCell{iZ}.area + GzSpoilersCell{iZ}.area;
                    dispersionsPerTR(iZ) = obj.calculatePhaseDispersion(areaTotal, partitionThickness);
                end
                
            else
                if phaseDispersionZ >= dispersionDueToGzPartitionMax/2
                    % use the same duration to keep same TR
                    AreaSpoilingZ_max = phaseDispersionZ / (2 * pi * partitionThickness);
                    dummyGradient = mr.makeTrapezoid('z',systemLimits,'Area',abs(AreaSpoilingZ_max));
                    fixedDurationGradient = mr.calcDuration(dummyGradient);
                else
                    AreaSpoilingZ_max = abs(phaseDispersionZ-dispersionDueToGzPartitionMax) / (2 * pi * partitionThickness);
                    dummyGradient = mr.makeTrapezoid('z',systemLimits,'Area',abs(AreaSpoilingZ_max));
                    fixedDurationGradient = mr.calcDuration(dummyGradient);
                end
                for ii=1:nPartitions
                    % GzPartition already add some phase dispersion to the spins
                    dispersionDueToThisPartition = obj.calculatePhaseDispersion(abs(GzPartitionsCell{ii}.area), partitionThickness);
                    % Then we calculate the phase dispersion needed to get phaseDispersionZ in total
                    dispersionNeededZ = abs(phaseDispersionZ - dispersionDueToThisPartition);
                    AreaSpoilingNeededZ = dispersionNeededZ / (2 * pi * partitionThickness);
                    haveSameSign1 = (GzPartitionsCell{ii}.area < 0 && (dispersionDueToThisPartition >= phaseDispersionZ));
                    haveSameSign2 = (GzPartitionsCell{ii}.area > 0 && (dispersionDueToThisPartition <= phaseDispersionZ));
                    if (haveSameSign1 || haveSameSign2)
                        GzSpoilersCell{ii} = mr.makeTrapezoid('z','Area',AreaSpoilingNeededZ,'Duration',fixedDurationGradient,'system',systemLimits);
                    else
                        GzSpoilersCell{ii} = mr.makeTrapezoid('z','Area',-AreaSpoilingNeededZ,'Duration',fixedDurationGradient,'system',systemLimits);
                    end
                    areaTotal = GzPartitionsCell{ii}.area + GzSpoilersCell{ii}.area;
                    dispersionsPerTR(ii) = obj.calculatePhaseDispersion(areaTotal, partitionThickness);
                end
            end
        end
        
        function SeqEvents = collectSequenceEvents(obj)
            [RF, ~, ~] = createSlabSelectionEvents(obj);
            GzCombinedCell = combineGzWithGzRephPlusPartitions(obj);
            [~, GxPre, ADC] = createReadoutEvents(obj);
            [GxPlusSpoiler,~] = createGxPlusSpoiler(obj);
            [GzSpoilersCell, ~] = createGzSpoilers(obj);
            
            SeqEvents.RF = RF;
            SeqEvents.GzCombinedCell = GzCombinedCell;
            SeqEvents.GxPre = GxPre;
            SeqEvents.GxPlusSpoiler = GxPlusSpoiler;
            SeqEvents.GzSpoilersCell = GzSpoilersCell;
            SeqEvents.ADC = ADC;
        end
        
        function AlignedSeqEvents = alignSeqEvents(obj)
            SeqEvents = collectSequenceEvents(obj);
            RF = SeqEvents.RF;
            GzCombinedCell = SeqEvents.GzCombinedCell;
            GxPre = SeqEvents.GxPre;
            GxPlusSpoiler = SeqEvents.GxPlusSpoiler;
            GzSpoilersCell = SeqEvents.GzSpoilersCell;
            ADC = SeqEvents.ADC;
            rfRingdownTime = obj.protocol.systemLimits.rfRingdownTime;
            gradRasterTime = obj.protocol.systemLimits.gradRasterTime;
            RfExcitation = obj.protocol.RfExcitation;
            
            % 1. fix the first block (RF, GzCombinedCell, and GxPre)
            if strcmp(RfExcitation,'nonSelective')
                delay = mr.calcDuration(RF) - rfRingdownTime;
                for ii =1:size(GzCombinedCell,2)
                    GzCombinedCell{ii}.delay = GzCombinedCell{ii}.delay + delay; %1.1
                end
            end
            
            durationGzCombined = mr.calcDuration(GzCombinedCell{1});
            durationGxPre = mr.calcDuration(GxPre);
            if durationGzCombined > durationGxPre
                % align GzRephPlusGzPartition and GxPre to the right
                addDelay = durationGzCombined - durationGxPre;
                GxPre.delay = GxPre.delay + (addDelay / gradRasterTime) * gradRasterTime; % 1.2
            end
            
            % 2 fix the second block (GxPlusSpoiler, ADC, GzSpoilersCell)
            % 2.1 add delay to the ADC event to appear at the same time as
            % the flat region of Gx
            ADC.delay = GxPlusSpoiler.riseTime;
            % 2.2 add delay to GzSpoliers to appear just after the flat
            % region of GxPlusSpoilers
            addDelay = GxPlusSpoiler.riseTime + GxPlusSpoiler.flatTime;
            for kk=1:size(GzSpoilersCell,2)
                GzSpoilersCell{kk}.delay = GzSpoilersCell{kk}.delay + addDelay; % GzSpoiler can appear after flat region of Gx in the same block
            end
            
            % return the aligned events in a struct
            AlignedSeqEvents.RF = RF;
            AlignedSeqEvents.GzCombinedCell = GzCombinedCell;
            AlignedSeqEvents.GxPre = GxPre;
            AlignedSeqEvents.GxPlusSpoiler = GxPlusSpoiler;
            AlignedSeqEvents.GzSpoilersCell = GzSpoilersCell;
            AlignedSeqEvents.ADC = ADC;
        end
        
        function RfPhasesRad = calculateRfPhasesRad(obj)
            nDummyScans = obj.protocol.nDummyScans;
            nSpokes = obj.protocol.nSpokes;
            nPartitions = obj.protocol.nPartitions;
            RfSpoilingIncrement = obj.protocol.RfSpoilingIncrement;
            
            nRfEvents = nDummyScans + nPartitions * nSpokes;
            index = 0:1:nRfEvents - 1;
            RfPhasesDeg = mod(0.5 * RfSpoilingIncrement * (index.^2 + index + 2), 360); % eq. (14.3) Bernstein 2004
            RfPhasesRad = RfPhasesDeg * pi / 180; % convert to radians.
        end
        
        function spokeAngles = calculateSpokeAngles(obj)
            %calculateSpokeAngles calculates the base spoke angles for one partition
            %depending on the number of spokes, angular ordering and the angle range.
            nSpokes = obj.protocol.nSpokes;
            angularOrdering = obj.protocol.angularOrdering;
            goldenAngleSequence = obj.protocol.goldenAngleSequence;
            angleRange = obj.protocol.angleRange;
            
            index = 0:1:nSpokes - 1;
            
            if strcmp(angularOrdering,'uniformAlternating')
                
                angularSamplingInterval = pi / nSpokes;
                spokeAngles = angularSamplingInterval * index; % array containing necessary angles for one partition
                spokeAngles(2:2:end) = spokeAngles(2:2:end) + pi; % add pi to every second spoke angle to achieved alternation
                
            else
                
                switch angularOrdering
                    case 'uniform'
                        angularSamplingInterval = pi / nSpokes;
                        
                    case 'goldenAngle'
                        tau = (sqrt(5) + 1) / 2; % golden ratio
                        N = goldenAngleSequence;
                        angularSamplingInterval = pi / (tau + N - 1);
                end
                
                spokeAngles = angularSamplingInterval * index; % array containing necessary angles for one partition
                
                switch angleRange
                    case 'fullCircle'
                        spokeAngles = mod(spokeAngles, 2 * pi); % projection angles in [0, 2*pi)
                    case 'halfCircle'
                        spokeAngles = mod(spokeAngles, pi); % projection angles in [0, pi)
                end
            end
        end
        
        function partitionRotationAngles = calculatePartitionRotationAngles(obj)
            %calculatePartitionRotationAngles calculates the angle offset across
            %partitions according to the parameter partitionRotation.
            nSpokes = obj.protocol.nSpokes;
            nPartitions = obj.protocol.nPartitions;
            partitionRotation = obj.protocol.partitionRotation;
            index = 0:1:nPartitions - 1;
            
            switch partitionRotation
                
                case 'aligned'
                    
                    partitionRotationAngles = zeros(1,nPartitions);
                    
                case 'linear'
                    
                    partitionRotationAngles = ( (pi / nSpokes) * (1 / nPartitions) ) * index;
                    
                case 'goldenAngle'
                    
                    partitionRotationAngles = ( (pi / nSpokes) * ((sqrt(5) - 1) / 2) ) * index;
                    partitionRotationAngles = mod(partitionRotationAngles, pi/nSpokes);
                    
            end
        end
        
        function [TE_min, TR_min]  = calculateMinTeTr(obj)
           %todo 
        end
        
        function sequenceKernel = createOneSequenceKernel(obj)
            %todo
        end
        
        function [allAngles, allPartitionIndx] = calculateAnglesForAllSpokes(obj)
            viewOrder = obj.protocol.viewOrder;
            nSpokes = obj.protocol.nSpokes;
            nPartitions = obj.protocol.nPartitions;
            nDummyScans = obj.protocol.nDummyScans;
            spokeAngles = calculateSpokeAngles(obj);
            partRotAngles = calculatePartitionRotationAngles(obj);
            
            counter = 1;
            angles = zeros(1, nSpokes * nPartitions);
            partitionIndx = zeros(1, nSpokes * nPartitions);
            switch viewOrder
                case 'partitionsInOuterLoop'                    
                    for iZ=1:nPartitions
                        for iR=1:nSpokes
                            angles(counter) = spokeAngles(iR) + partRotAngles(iZ);
                            partitionIndx(counter) = iZ;
                            counter = counter + 1;
                        end
                    end
                case 'partitionsInInnerLoop'                    
                    for iR=1:nSpokes
                        for iZ=1:nPartitions
                            angles(counter) = spokeAngles(iR) + partRotAngles(iZ);
                            partitionIndx(counter) = iZ;
                            counter = counter + 1;
                        end
                    end
            end
            
            if nDummyScans > 0
                allAngles = [angles(1:nDummyScans) angles]; % replicate the first nDummyScans angles for the dummy scans
                allPartitionIndx = [partitionIndx(1:nDummyScans) partitionIndx]; % replicate the first partitionIndx indexes for the dummy scans
            else
                allAngles = angles;
                allPartitionIndx = partitionIndx;
            end
        end
        
        function sequenceObject = createSequenceObject(obj)
            isValidated = obj.protocol.isValidated;            
            if ~isValidated
                msg = 'The input parameters must be validated first.';
                error(msg)
            end
            
            [allAngles, allPartitionIndx] = calculateAnglesForAllSpokes(obj);            
            RfPhasesRad = calculateRfPhasesRad(obj);
            [delayTE, delayTR] = calculateTeAndTrDelays(obj);
            nDummyScans = obj.protocol.nDummyScans;
            
            AlignedSeqEvents = alignSeqEvents(obj);
            RF = AlignedSeqEvents.RF;
            GzCombinedCell = AlignedSeqEvents.GzCombinedCell;
            GxPre = AlignedSeqEvents.GxPre;
            GxPlusSpoiler = AlignedSeqEvents.GxPlusSpoiler;
            GzSpoilersCell = AlignedSeqEvents.GzSpoilersCell;
            ADC = AlignedSeqEvents.ADC;
            
            % last alignement to have 
            GxPre.delay = GxPre.delay + delayTE;
            
            sequenceObject = mr.Sequence();
            RFcounter = 1; % to keep track of the number of applied RF pulses.
            durationSecondBlock = delayTR + mr.calcDuration(GxPlusSpoiler, GzSpoilersCell{1});
            for iF = 1:length(allAngles)                
                iZ = allPartitionIndx(iF);
                RF.phaseOffset = RfPhasesRad(RFcounter);
                ADC.phaseOffset = RfPhasesRad(RFcounter);
                                
                    sequenceObject.addBlock( mr.rotate('z', allAngles(iF), RF, GzCombinedCell{iZ},GxPre) );
                if iF > nDummyScans % include ADC events
                    sequenceObject.addBlock( mr.rotate('z', allAngles(iF), GxPlusSpoiler, ADC, GzSpoilersCell{iZ}, mr.makeDelay(durationSecondBlock)) );                    
                else % no ADC event
                    sequenceObject.addBlock( mr.rotate('z', allAngles(iF), GxPlusSpoiler, GzSpoilersCell{iZ}, mr.makeDelay(durationSecondBlock)) );
                end 
                
                RFcounter = RFcounter + 1;                
            end 
        end
        
        function simulateSequence(obj)            
            viewOrder = obj.protocol.viewOrder;   
            nPartitions = obj.protocol.nPartitions;
            newObj = obj;
            
            newObj.protocol.nDummyScans = 5;
            newObj.protocol.nPartitions = obj.protocol.nPartitions_min;
            switch viewOrder                
            case 'partitionsInOuterLoop'
                newObj.protocol.nSpokes = 21; 
            case 'partitionsInInnerLoop'
                newObj.protocol.nSpokes = 21;                
            end
            fprintf('**Testing the sequence with: %s,\n',viewOrder);
            fprintf('  nDummyScans: %i\n',newObj.protocol.nDummyScans);
            fprintf('  nSpokes: %i\n',newObj.protocol.nSpokes);
            fprintf('  nPartitions: %i\n\n',newObj.protocol.nPartitions);
            
            writeSequence(newObj);
            giveTestingInfo(newObj)
        end
        
        function writeSequence(obj)
            FOV = obj.protocol.FOV;
            slabThickness = obj.protocol.slabThickness;
            sequenceObject = createSequenceObject(obj);
            
            sequenceObject.setDefinition('FOV', [FOV FOV slabThickness]);
            sequenceObject.setDefinition('Name', '3D_radial_stackOfStars');
            sequenceObject.write('3D_radial_stackOfStars.seq');
            saveInfo4Reco(obj);
            obj.giveInfoAboutSequence
        end
        
        function saveInfo4Reco(obj)
            info4Reco.FOV = obj.protocol.FOV;
            info4Reco.nSamples = obj.protocol.nSamples;
            info4Reco.nPartitions = obj.protocol.nPartitions;
            info4Reco.readoutOversampling = obj.protocol.readoutOversampling;
            info4Reco.nSpokes = obj.protocol.nSpokes;
            info4Reco.viewOrder = obj.protocol.viewOrder;
            info4Reco.spokeAngles = calculateSpokeAngles(obj);
            info4Reco.partitionRotationAngles = calculatePartitionRotationAngles(obj);
            save('info4RecoSoS.mat','info4Reco');
        end
        
        function giveTestingInfo(obj)
            gradRasterTime = obj.protocol.systemLimits.gradRasterTime;
            sequenceObject = createSequenceObject(obj);
            sequenceObject.plot();
            % seq.sound();
            
            % trajectory calculation
            [ktraj_adc, ktraj, t_excitation, t_refocusing, t_adc] = sequenceObject.calculateKspace();
            
            % plot k-spaces
            time_axis = (1:(size(ktraj,2))) * gradRasterTime;
            figure; plot(time_axis, ktraj'); % plot the entire k-space trajectory
            hold; plot(t_adc,ktraj_adc(1,:),'.'); % and sampling points on the kx-axis
            figure; plot(ktraj(1,:),ktraj(2,:),'b'); % a 2D plot
            axis('equal'); % enforce aspect ratio for the correct trajectory display
            hold; plot(ktraj_adc(1,:),ktraj_adc(2,:),'r.'); % plot the sampling points
            
            % very optional slow step, but useful for testing during development e.g. for the real TE, TR or for staying within slewrate limits
            rep = sequenceObject.testReport;
            fprintf([rep{:}]);
        end
        
    end
    
    methods(Static)
        function giveInfoAboutSequence()
            fprintf('## Creating the sequence...\n');
            fprintf('**GzReph and GzPartition are merged.\n');
            fprintf('**G_readout and G_readoutSpoiler are merged.\n');
            fprintf('## ...Done\n');
        end
   end
    
end




