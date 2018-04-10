function Y = phate(data, varargin)
% phate  Run PHATE for visualizing noisy non-linear data in lower dimensions
%   Y = phate(data) runs PHATE on data (rows: samples, columns: features)
%   with default parameter settings and returns a 2 dimensional embedding.
%
%   [...] = phate(..., 'PARAM1',val1, 'PARAM2',val2, ...) allows you to
%   specify optional parameter name/value pairs that control further details
%   of PHATE.  Parameters are:
%
%   'ndim' - number of (output) embedding dimensions. Common values are 2
%   or 3. Deafults to 2.
%
%   'k' - number of nearest neighbors of the knn graph. Deafults to 10.
%
%   't' - number of diffusion steps. Defaults to [] wich autmatically picks
%   the optimal t.
%
%   't_max' - maximum t for finding optimal t. if t = [] optimal t will be
%   computed by computing Von Neumann Entropy for each t <= t_max and then
%   picking the kneepoint.
%
%   'npca' - number of pca components for computing distances. Defaults to
%   100.
%
%   'mds_method' - method of multidimensional scaling. Choices are:
%
%       'mmds' - metric MDS (default)
%       'cmds' - classical MDS
%       'nmmds' - non-metric MDS
%
%   'distfun' - distance function. Deafult is 'euclidean'.
%
%   'distfun_mds' - distance function for MDS. Deafult is 'euclidean'.
%
%   'pot_method' - method of computing the PHATE potential dstance. Choices
%   are:
%
%       'log' - -log(P + eps). (default)
%
%       'sqrt' - sqrt(P).
%
%   'n_landmarks' - number of landmarks for fast and scalable PHATE. [] or
%   n_landmarks = npoints does no landmarking, which is slower. More
%   landmarks is more accurate but comes at the cost of speed and memory.
%   Defaults to 1000.
%
%   'nsvd' - number of singular vectors for spectral clustering (for
%   computing landmarks). Defaults to 100.
%
%   'operator' - user supplied operator. If not given ([]) operator is
%   computed from the supplied data. Supplied operator should be a square
%   row stochastic samples by samples affinity matrix. Deafults to [].

npca = 100;
k = 10;
nsvd = 100;
n_landmarks = 1000;
ndim = 2;
t = [];
mds_method = 'mmds';
distfun = 'euclidean';
distfun_mds = 'euclidean';
pot_method = 'log';
P = [];
Pnm = [];
t_max = 100;

% get input parameters
for i=1:length(varargin)
    % k for knn adaptive sigma
    if(strcmp(varargin{i},'k'))
       k = lower(varargin{i+1});
    end
    % diffusion time
    if(strcmp(varargin{i},'t'))
       t = lower(varargin{i+1});
    end
    % t_max for VNE
    if(strcmp(varargin{i},'t_max'))
       t_max = lower(varargin{i+1});
    end
    % Number of pca components
    if(strcmp(varargin{i},'npca'))
       npca = lower(varargin{i+1});
    end
    % Number of dimensions for the PHATE embedding
    if(strcmp(varargin{i},'ndim'))
       ndim = lower(varargin{i+1});
    end
    % Method for MDS
    if(strcmp(varargin{i},'mds_method'))
       mds_method =  varargin{i+1};
    end
    % Distance function for the inputs
    if(strcmp(varargin{i},'distfun'))
       distfun = lower(varargin{i+1});
    end
    % distfun for MDS
    if(strcmp(varargin{i},'distfun_mds'))
       distfun_mds =  lower(varargin{i+1});
    end
    % nsvd for spectral clustering
    if(strcmp(varargin{i},'nsvd'))
       nsvd = lower(varargin{i+1});
    end
    % n_landmarks for spectral clustering
    if(strcmp(varargin{i},'n_landmarks'))
       n_landmarks = lower(varargin{i+1});
    end
    % potential method: log, sqrt
    if(strcmp(varargin{i},'pot_method'))
       pot_method = lower(varargin{i+1});
    end
    % operator
    if(strcmp(varargin{i},'operator'))
       P = lower(varargin{i+1});
    end
end

if isempty(P)
    if ~isempty(npca)
        % PCA
        disp 'Doing PCA'
        pc = svdpca(data, npca, 'random');
    else
        pc = data;
    end
    % diffusion operator
    P = compute_operator_fast(pc, 'k', k, 'distfun', distfun);
else
    disp 'Using supplied operator'
end

if ~isempty(n_landmarks) && n_landmarks < size(pc,1)
    % spectral cluster for landmarks
    disp 'Spectral clustering for landmarks'
    [U,S,~] = randPCA(P, nsvd);
    IDX = kmeans(U*S, n_landmarks);
    
    % create landmark operators
    disp 'Computing landmark operators'
    n = size(P,1);
    m = max(IDX);
    Pnm = nan(n,m);
    Pmn = nan(m,n);
    for I=1:m
        Pnm(:,I) = sum(P(:,IDX==I),2);
        Pmn(I,:) = sum(P(IDX==I,:),1);
    end
    Pmn = bsxfun(@rdivide, Pmn, sum(Pmn,2));
    
    % Pmm
    Pmm = Pmn * Pnm;
else
    disp 'Running PHATE without landmarking'
    Pmm = P;
end

% VNE
disp 'Finding optimal t using VNE'
if isempty(t)
    t = vne_optimal_t(Pmm, t_max);
end

% diffuse
disp 'Diffusing landmark operators'
P_t = Pmm^t;

% potential distances
disp 'Computing potential distances'
switch pot_method
    case 'log'
        P_t(P_t<=eps) = eps;
        Pot = -log(P_t);
    case 'sqrt'
        Pot = sqrt(P_t);
    otherwise
        disp 'potential method unknown'
end
PDX = squareform(pdist(Pot, distfun_mds));

% CMDS
disp 'Doing classical MDS'
Y = randmds(PDX, ndim);

% MMDS
if strcmpi(mds_method, 'mmds')
    disp 'Doing metric MDS:'
    opt = statset('display','iter');
    Y = mdscale(PDX,ndim,'options',opt,'start',Y,'Criterion','metricstress');
end

% NMMDS
if strcmpi(mds_method, 'nmmds')
    disp 'Doing non-metric MDS:'
    opt = statset('display','iter');
    Y = mdscale(PDX,ndim,'options',opt,'start',Y,'Criterion','stress');
end

if ~isempty(Pnm)
    % out of sample extension from landmarks to all points
    disp 'Out of sample extension from landmakrs to all points'
    Y = Pnm * Y;
end

disp 'Done.'

end






