function A7_miniCAD()
    % Creazione della finestra moderna
    fig = uifigure('Name', 'Mini-CAD Moderno', 'Position', [100 100 800 600]);

    % Creazione degli assi moderni (specificando il parent)
    ax = uiaxes(fig, 'Position', [50 50 700 500]);

    % Configurazione assi
    axis(ax, 'equal');
    hold(ax, 'on');
    ax.XLim = [-5 35]; ax.YLim = [-5 25];
    ax.XGrid = 'on'; ax.YGrid = 'on';
    ax.XMinorGrid = 'on'; ax.YMinorGrid = 'on';
    ax.Clipping = 'on';

    % Stato dell'app
    S.tool = 'none';
    S.tempPoint = [];
    S.preview = gobjects(0);
    S.ax = ax;

    % (NEW) database oggetti e selezione
    S.objects  = gobjects(0);
    S.selected = gobjects(0);

    fig.UserData = S;

    % Callback moderne
    fig.WindowButtonDownFcn = @onMouseDown;
    fig.WindowKeyPressFcn   = @onKeyPress;
    fig.WindowButtonMotionFcn = @onMouseMove;

    % --- Funzioni Nested ---

    function onKeyPress(src, evt)
        S = src.UserData;
        key = lower(evt.Key);

        switch key
            case 'l'
                S.tool = 'line';   disp("Tool: LINEA");
            case 'r'
                S.tool = 'rec';    disp("Tool: RETTANGOLO");
            case 'c'
                S.tool = 'circle'; disp("Tool: CERCHIO");
            case 's'
                S.tool = 'select'; disp("Tool: SELEZIONE");
                S.tempPoint = [];
                S = clearPreview(S);
            case 'escape'
                S.tool = 'none'; disp("Tool: RESET");
                S.tempPoint = [];
                S = clearPreview(S);
                S = clearSelection(S);
            case {'delete','backspace'}
                % (NEW) cancella selezionati
                S = deleteSelected(S);
        end

        S = pruneHandles(S);
        src.UserData = S;
    end

    function onMouseDown(src, ~)
        S = src.UserData;

        % (NEW) se siamo in SELECT, click nel vuoto = deselect
        if strcmp(S.tool, 'select')
            % se il click non ha colpito un oggetto, deseleziona
            obj = src.CurrentObject;
            if isempty(obj) || ~isgraphics(obj) || ~isCadObject(obj)
                S = clearSelection(S);
            end
            src.UserData = S;
            return;
        end

        % modalità disegno: prendi il punto SOLO se dentro ax
        p = getMousePoint(S.ax);
        if ~isPointInsideAxes(S.ax, p)
            return;
        end

        if strcmp(S.tool, 'none')
            return;
        end

        if isempty(S.tempPoint)
            S.tempPoint = p; % Primo click
        else
            % Secondo click: Disegno definitivo
            h = drawShape(S.ax, S.tool, S.tempPoint, p, 'k');
            h = finalizeObject(h, S.tool, src);  % (NEW) tag + callback
            S.objects(end+1) = h;

            S.tempPoint = [];
            S = clearPreview(S);
        end

        S = pruneHandles(S);
        src.UserData = S;
    end

    function onMouseMove(src, ~)
        S = src.UserData;

        % (NEW) in SELECT niente preview
        if strcmp(S.tool, 'select')
            return;
        end

        if isempty(S.tempPoint) || strcmp(S.tool, 'none')
            return;
        end

        p = getMousePoint(S.ax);

        % (NEW) preview solo se dentro ax
        if ~isPointInsideAxes(S.ax, p)
            S = clearPreview(S);
            src.UserData = S;
            return;
        end

        % Gestione Anteprima
        if isempty(S.preview) || ~isgraphics(S.preview)
            S.preview = drawShape(S.ax, S.tool, S.tempPoint, p, [0, 0.447, 0.741]);
            % (NEW) preview non selezionabile
            setNonPickable(S.preview);
        else
            updateShape(S.preview, S.tool, S.tempPoint, p);
        end

        src.UserData = S;
    end

end

% --- Funzioni di Supporto (Esterne) ---

function h = drawShape(ax, tool, p1, p2, color)
    switch tool
        case 'line'
            h = line(ax, [p1(1) p2(1)], [p1(2) p2(2)], 'Color', color);
        case 'rec'
            h = patch(ax, 'XData', [p1(1) p2(1) p2(1) p1(1)], ...
                         'YData', [p1(2) p1(2) p2(2) p2(2)], ...
                         'FaceColor', 'none', 'EdgeColor', color);
        case 'circle'
            r = norm(p1 - p2);
            theta = linspace(0, 2*pi, 100);
            h = plot(ax, p1(1) + r*cos(theta), p1(2) + r*sin(theta), 'Color', color);
        otherwise
            h = gobjects(0);
    end
end

function updateShape(h, tool, p1, p2)
    switch tool
        case 'line'
            h.XData = [p1(1) p2(1)];
            h.YData = [p1(2) p2(2)];
        case 'rec'
            h.XData = [p1(1) p2(1) p2(1) p1(1)];
            h.YData = [p1(2) p1(2) p2(2) p2(2)];
        case 'circle'
            r = norm(p1 - p2);
            theta = linspace(0, 2*pi, 100);
            h.XData = p1(1) + r*cos(theta);
            h.YData = p1(2) + r*sin(theta);
    end
end

function p = getMousePoint(ax)
    cp = ax.CurrentPoint;
    p = cp(1, 1:2);
end

function tf = isPointInsideAxes(ax, p)
    tf = p(1) >= ax.XLim(1) && p(1) <= ax.XLim(2) && ...
         p(2) >= ax.YLim(1) && p(2) <= ax.YLim(2);
end

function S = clearPreview(S)
    if ~isempty(S.preview) && isgraphics(S.preview)
        delete(S.preview);
    end
    S.preview = gobjects(0);
end

% -------------------- (NEW) Selezione --------------------

function h = finalizeObject(h, tool, fig)
    % Tag per riconoscere gli oggetti CAD
    h.Tag = "cad_" + string(tool);

    % Salva stile originale per ripristino
    ud = struct();
    ud.tool = tool;
    ud.orig = captureStyle(h);
    h.UserData = ud;

    % Rendi cliccabile + callback
    if isprop(h,'PickableParts'), h.PickableParts = 'visible'; end
    if isprop(h,'HitTest'),       h.HitTest = 'on'; end
    h.ButtonDownFcn = @(src,evt)onObjectClicked(fig, src, evt);
end

function onObjectClicked(fig, obj, evt)
    S = fig.UserData;
    if ~strcmp(S.tool, 'select')
        return; % clic ignorato se non siamo in modalità selezione
    end

    if ~isCadObject(obj)
        return;
    end

    mods = fig.CurrentModifier;                  % <-- uifigure: fonte affidabile
isShift = any(strcmpi(mods, 'shift'));

    S = pruneHandles(S);

    if ~isShift
        % selezione singola: svuota e seleziona solo questo
        S = clearSelection(S);
        S = addSelection(S, obj);
    else
        % shift: toggle
        if any(S.selected == obj)
            S = removeSelection(S, obj);
        else
            S = addSelection(S, obj);
        end
    end

    fig.UserData = S;
end

function tf = isCadObject(h)
    tf = isgraphics(h) && isprop(h,'Tag') && startsWith(string(h.Tag), "cad_");
end

function S = addSelection(S, obj)
    if any(S.selected == obj), return; end
    S.selected(end+1) = obj;
    applySelectedStyle(obj, true);
end

function S = removeSelection(S, obj)
    idx = (S.selected == obj);
    if any(idx)
        applySelectedStyle(obj, false);
        S.selected(idx) = [];
    end
end

function S = clearSelection(S)
    if ~isempty(S.selected)
        for k = 1:numel(S.selected)
            if isgraphics(S.selected(k))
                applySelectedStyle(S.selected(k), false);
            end
        end
    end
    S.selected = gobjects(0);
end

function S = deleteSelected(S)
    S = pruneHandles(S);
    if isempty(S.selected), return; end

    % cancella graficamente
    delete(S.selected);

    % pulizia liste
    S.selected = gobjects(0);
    S = pruneHandles(S);
end

function S = pruneHandles(S)
    if isfield(S,'objects') && ~isempty(S.objects)
        S.objects = S.objects(isgraphics(S.objects));
    end
    if isfield(S,'selected') && ~isempty(S.selected)
        S.selected = S.selected(isgraphics(S.selected));
    end
end

function st = captureStyle(h)
    st = struct();
    if isprop(h,'Color'),     st.Color = h.Color; end
    if isprop(h,'LineWidth'), st.LineWidth = h.LineWidth; end
    if isprop(h,'LineStyle'), st.LineStyle = h.LineStyle; end
    if isprop(h,'EdgeColor'), st.EdgeColor = h.EdgeColor; end
end

function applySelectedStyle(h, selected)
    if ~isgraphics(h), return; end

    % ripristino dallo stile salvato
    if ~selected
        if isprop(h,'UserData') && isstruct(h.UserData) && isfield(h.UserData,'orig')
            st = h.UserData.orig;
            if isfield(st,'Color') && isprop(h,'Color'),         h.Color = st.Color; end
            if isfield(st,'LineWidth') && isprop(h,'LineWidth'), h.LineWidth = st.LineWidth; end
            if isfield(st,'LineStyle') && isprop(h,'LineStyle'), h.LineStyle = st.LineStyle; end
            if isfield(st,'EdgeColor') && isprop(h,'EdgeColor'), h.EdgeColor = st.EdgeColor; end
        end
        return;
    end

    % stile selezionato
    if isprop(h,'LineWidth'), h.LineWidth = 2; end
    if isprop(h,'LineStyle'), h.LineStyle = '-'; end
    if isprop(h,'Color'),     h.Color = [1 0 0]; end
    if isprop(h,'EdgeColor'), h.EdgeColor = [1 0 0]; end
end

function setNonPickable(h)
    if ~isgraphics(h), return; end
    if isprop(h,'PickableParts'), h.PickableParts = 'none'; end
    if isprop(h,'HitTest'),       h.HitTest = 'off'; end
end
