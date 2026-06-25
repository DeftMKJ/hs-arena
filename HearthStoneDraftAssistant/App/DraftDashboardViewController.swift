import Photos
import PhotosUI
import SDWebImage
import SnapKit
import UniformTypeIdentifiers
import UIKit

final class DraftDashboardViewController: UIViewController {
    // MARK: - CollectionView Section

    enum Section: Int, CaseIterable {
        case toolbar    // 工具栏
        case status     // 状态栏
        case chips      // 职业 chips（横向滚动）
        case inputs     // 三个输入框
        case recommend  // 推荐面板（有数据时显示）
        case cards      // 三张卡片（固定高度 500）
        case log        // 可折叠日志区
    }

    private let dataService = DraftDataService.live()
    #if targetEnvironment(macCatalyst)
    private let logWatcher = HearthstoneLogWatcher()
    private let screenshotFolderWatcher = ScreenshotFolderWatcher()
    private let screenshotRecognizer: DraftScreenshotRecognizing = OpenCVDraftScreenshotRecognizer()
    #else
    private let screenshotRecognizer: DraftScreenshotRecognizing = VisionOnlyDraftScreenshotRecognizer()
    #endif
    private let classOptions: [(arenaClass: ArenaClass, title: String)] = [
        (.mage, "法师"),
        (.hunter, "猎人"),
        (.deathKnight, "死亡骑士"),
        (.rogue, "潜行者"),
        (.druid, "德鲁伊"),
        (.paladin, "圣骑士"),
        (.priest, "牧师"),
        (.shaman, "萨满"),
        (.warlock, "术士"),
        (.warrior, "战士"),
        (.demonHunter, "恶魔猎手")
    ]
    private let titleLabel = UILabel()
    private let inspectButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private let compareButton = UIButton(type: .system)
    private let guideButton = UIButton(type: .system)
    #if targetEnvironment(macCatalyst)
    private let logWatcherButton = UIButton(type: .system)
    private let screenshotButton = UIButton(type: .system)
    private let autoWatchButton = UIButton(type: .system)
    #else
    private let cameraButton = UIButton(type: .system)
    private let albumButton = UIButton(type: .system)
    #endif
    private let clearButton = UIButton(type: .system)
    private let toolbarContainer = UIView()
    private let logStatusBar = UIView()
    private let logStatusIcon = UILabel()
    private let logStatusLabel = UILabel()

    private var selectedClassIndexes: Set<Int> = [0]
    private var confirmedArenaClasses: [ArenaClass] = [.mage]
    private var cardInputTexts: [String] = ["", "", ""]
    private let recommendationPanel = UIView()
    private let recommendationTitleLabel = UILabel()
    private let recommendationReasonLabel = UILabel()

    private let resultView = UITextView()

    #if targetEnvironment(macCatalyst)
    // 监听路径配置 UI（Mac 专用）
    private let watchPathsPanel = UIView()
    private var watchPathRows: [UIView] = []
    private var folderPickerDelegate: FolderPickerDelegate?
    private var isWatchingLogs = false
    private var isAutoWatching = false
    private var draftWindowExpiresAt: Date?
    private var screenshotPickerDelegate: DraftScreenshotPickerDelegate?
    #else
    private var phPickerDelegate: IOSPhotoPickerDelegate?
    #endif

    // MARK: - CollectionView 架构

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, ItemID>!
    private var isLogExpanded = false
    private var currentCardDisplays: [DraftCardDisplayModel] = []
    private var currentRecommendationTitle = ""
    private var currentRecommendationReason = ""
    private var showRecommendation = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "竞技场选牌助手"
        view.backgroundColor = .systemBackground
        configureImageCache()
        configureViews()
        configureCollectionView()
        applyInitialSnapshot()
        bootstrapData()
    }

    private func configureImageCache() {
        SDImageCache.shared.config.maxMemoryCost = 60 * 1024 * 1024
        SDImageCache.shared.config.maxDiskSize = 300 * 1024 * 1024
        SDImageCache.shared.config.maxDiskAge = 60 * 60 * 24 * 30
        SDWebImageDownloader.shared.config.downloadTimeout = 20
    }

    private func configureViews() {
        titleLabel.text = "竞技场选牌助手"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true

        configureToolbar()
        configureLogStatusBar()
        #if targetEnvironment(macCatalyst)
        configureWatchPathsPanel()
        #endif
        configureClassChips()
        configureRecommendationPanel()



        resultView.isEditable = false
        resultView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        resultView.backgroundColor = .secondarySystemBackground
        resultView.layer.cornerRadius = 8
        resultView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        resultView.text = "正在加载数据源状态..."
    }

    private func configureToolbar() {
        toolbarContainer.backgroundColor = .secondarySystemBackground
        toolbarContainer.layer.cornerRadius = 14

        #if targetEnvironment(macCatalyst)
        let items: [(button: UIButton, image: String, label: String, action: Selector)] = [
            (inspectButton,    "tray.and.arrow.down", "数据源", #selector(inspectDataSources)),
            (refreshButton,    "arrow.clockwise",     "刷新",   #selector(refreshData)),
            (compareButton,    "chart.bar.xaxis",     "对比",   #selector(compareScores)),
            (guideButton,      "info.circle",         "说明",   #selector(showSourceGuide)),
            (logWatcherButton, "eye",                 "监听",   #selector(toggleLogWatcher)),
            (screenshotButton, "photo.badge.plus",    "导入",   #selector(importScreenshot)),
            (autoWatchButton,  "camera.viewfinder",   "自动",   #selector(toggleAutoWatch)),
            (clearButton,      "xmark.circle",        "清空",   #selector(clearResults)),
        ]
        configureToolbarMac(items: items, separatorIndex: 4)
        #else
        let items: [(button: UIButton, image: String, label: String, action: Selector)] = [
            (inspectButton, "tray.and.arrow.down", "数据源", #selector(inspectDataSources)),
            (refreshButton, "arrow.clockwise",     "刷新",   #selector(refreshData)),
            (compareButton, "chart.bar.xaxis",     "对比",   #selector(compareScores)),
            (guideButton,   "info.circle",         "说明",   #selector(showSourceGuide)),
            (cameraButton,  "camera",              "拍照",   #selector(takePhoto)),
            (albumButton,   "photo.on.rectangle",  "相册",   #selector(pickFromAlbum)),
            (clearButton,   "xmark.circle",        "清空",   #selector(clearResults)),
        ]
        configureToolbariOS(items: items)
        #endif
    }

    // Mac：所有按钮等宽平铺，中间加分隔线
    private func configureToolbarMac(
        items: [(button: UIButton, image: String, label: String, action: Selector)],
        separatorIndex: Int
    ) {
        var arranged: [UIView] = []
        for (i, item) in items.enumerated() {
            if i == separatorIndex {
                let sep = UIView()
                sep.backgroundColor = .separator
                toolbarContainer.addSubview(sep)
                sep.snp.makeConstraints { make in
                    make.width.equalTo(1)
                    make.height.equalTo(24)
                    make.centerY.equalToSuperview()
                }
                arranged.append(sep)
            }
            let btn = item.button
            btn.configuration = makeToolbarButtonConfig(image: item.image, label: item.label)
            btn.addTarget(self, action: item.action, for: .touchUpInside)
            toolbarContainer.addSubview(btn)
            btn.snp.makeConstraints { make in make.top.bottom.equalToSuperview() }
            arranged.append(btn)
        }
        let buttons = arranged.compactMap { $0 as? UIButton }
        var previous: UIView?
        for view in arranged {
            view.snp.makeConstraints { make in
                if let previous { make.leading.equalTo(previous.snp.trailing) }
                else { make.leading.equalToSuperview() }
            }
            previous = view
        }
        previous?.snp.makeConstraints { make in make.trailing.equalToSuperview() }
        if let first = buttons.first {
            for btn in buttons.dropFirst() {
                btn.snp.makeConstraints { make in make.width.equalTo(first) }
            }
        }
    }

    // iOS：所有按钮等宽平铺，用 UIStackView 铺满 toolbarContainer（无需滑动）
    private func configureToolbariOS(
        items: [(button: UIButton, image: String, label: String, action: Selector)]
    ) {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        toolbarContainer.addSubview(stack)
        stack.snp.makeConstraints { make in make.edges.equalToSuperview() }

        for item in items {
            let btn = item.button
            btn.configuration = makeToolbarButtonConfig(image: item.image, label: item.label)
            btn.addTarget(self, action: item.action, for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
    }

    private func makeToolbarButtonConfig(image: String, label: String) -> UIButton.Configuration {
        var cfg = UIButton.Configuration.plain()
        cfg.image = UIImage(systemName: image)
        cfg.title = label
        cfg.imagePlacement = .top
        cfg.imagePadding = 3
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var out = attr; out.font = UIFont.systemFont(ofSize: 10, weight: .medium); return out
        }
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        return cfg
    }

    private func setToolbarButtonStyle(
        _ button: UIButton,
        image: String,
        label: String,
        activeColor: UIColor? = nil
    ) {
        var cfg = makeToolbarButtonConfig(image: image, label: label)
        if let color = activeColor { cfg.baseForegroundColor = color }
        button.configuration = cfg
    }

    private func configureLogStatusBar() {
        logStatusBar.backgroundColor = .secondarySystemBackground
        logStatusBar.layer.cornerRadius = 10
        logStatusBar.clipsToBounds = true

        logStatusIcon.text = "●"
        logStatusIcon.font = .systemFont(ofSize: 10, weight: .bold)
        logStatusIcon.textColor = .systemGray3

        logStatusLabel.text = "日志监听未启动"
        logStatusLabel.font = .preferredFont(forTextStyle: .caption1)
        logStatusLabel.textColor = .secondaryLabel
        logStatusLabel.numberOfLines = 1
        logStatusLabel.lineBreakMode = .byTruncatingTail

        logStatusBar.addSubview(logStatusIcon)
        logStatusBar.addSubview(logStatusLabel)
        logStatusIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }
        logStatusLabel.snp.makeConstraints { make in
            make.leading.equalTo(logStatusIcon.snp.trailing).offset(6)
            make.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }
    }

    #if targetEnvironment(macCatalyst)
    private func configureWatchPathsPanel() {
        // 监听路径面板在 CollectionView 架构下暂不展示，保留对象但不进入视图层级。
        watchPathsPanel.isHidden = true
        watchPathsPanel.backgroundColor = .secondarySystemBackground
        watchPathsPanel.layer.cornerRadius = 12
        refreshWatchPathRows()
    }

    private func refreshWatchPathRows() {
        // 纯 Auto Layout 的垂直堆叠（不使用 UIStackView），仅用于保留原有路径管理逻辑。
        watchPathsPanel.subviews.forEach { $0.removeFromSuperview() }
        watchPathRows.removeAll()

        let headerLabel = UILabel()
        headerLabel.text = "自动截图监听路径"
        headerLabel.font = .preferredFont(forTextStyle: .subheadline)
        headerLabel.textColor = .label
        watchPathsPanel.addSubview(headerLabel)
        headerLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(12)
            make.leading.trailing.equalToSuperview().inset(12)
        }

        Task { [weak self] in
            guard let self else { return }
            let paths = await screenshotFolderWatcher.currentWatchedPaths()
            await MainActor.run {
                var previous: UIView = headerLabel
                for (index, path) in paths.enumerated() {
                    let row = self.makePathRow(path: path, index: index, total: paths.count)
                    self.watchPathsPanel.addSubview(row)
                    row.snp.makeConstraints { make in
                        make.top.equalTo(previous.snp.bottom).offset(6)
                        make.leading.trailing.equalToSuperview().inset(12)
                    }
                    self.watchPathRows.append(row)
                    previous = row
                }
                let addButton = UIButton(type: .system)
                addButton.setTitle("＋ 添加路径", for: .normal)
                addButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
                addButton.addTarget(self, action: #selector(self.addWatchPath), for: .touchUpInside)
                self.watchPathsPanel.addSubview(addButton)
                addButton.snp.makeConstraints { make in
                    make.top.equalTo(previous.snp.bottom).offset(6)
                    make.leading.trailing.equalToSuperview().inset(12)
                    make.bottom.equalToSuperview().inset(12)
                }
            }
        }
    }

    private func makePathRow(path: URL, index: Int, total: Int) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = path.path
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle

        let deleteButton = UIButton(type: .system)
        deleteButton.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        deleteButton.tintColor = total <= 1 ? .systemGray3 : .systemRed
        deleteButton.isEnabled = total > 1
        deleteButton.tag = index
        deleteButton.addTarget(self, action: #selector(removeWatchPath(_:)), for: .touchUpInside)

        container.addSubview(label)
        container.addSubview(deleteButton)

        deleteButton.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.width.height.equalTo(28)
        }
        label.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.equalTo(deleteButton.snp.leading).offset(-6)
        }
        return container
    }

    @objc private func addWatchPath() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        let delegate = FolderPickerDelegate(
            onPick: { [weak self] url in
                guard let self else { return }
                Task {
                    let current = await self.screenshotFolderWatcher.currentWatchedPaths()
                    guard !current.contains(url) else { return }
                    await self.screenshotFolderWatcher.setWatchedPaths(current + [url])
                    await MainActor.run { self.refreshWatchPathRows() }
                }
            }
        )
        folderPickerDelegate = delegate
        picker.delegate = delegate
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func removeWatchPath(_ sender: UIButton) {
        let index = sender.tag
        Task { [weak self] in
            guard let self else { return }
            var paths = await screenshotFolderWatcher.currentWatchedPaths()
            guard paths.indices.contains(index) else { return }
            paths.remove(at: index)
            await screenshotFolderWatcher.setWatchedPaths(paths)
            await MainActor.run { self.refreshWatchPathRows() }
        }
    }
    #endif

    // MARK: - CollectionView 布局与数据源

    private func configureCollectionView() {
        let layout = makeCompositionalLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        #if !targetEnvironment(macCatalyst)
        collectionView.contentInsetAdjustmentBehavior = .automatic
        #endif
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            #if targetEnvironment(macCatalyst)
            make.edges.equalTo(view.safeAreaLayoutGuide)
            #else
            make.edges.equalToSuperview()
            #endif
        }

        registerCells()
        configureDataSource()
    }

    private func registerCells() {
        collectionView.register(ToolbarCell.self, forCellWithReuseIdentifier: ToolbarCell.reuseID)
        collectionView.register(StatusBarCell.self, forCellWithReuseIdentifier: StatusBarCell.reuseID)
        collectionView.register(ClassChipCell.self, forCellWithReuseIdentifier: ClassChipCell.reuseID)
        collectionView.register(InputFieldCell.self, forCellWithReuseIdentifier: InputFieldCell.reuseID)
        collectionView.register(RecommendationCell.self, forCellWithReuseIdentifier: RecommendationCell.reuseID)
        collectionView.register(CardChoiceCell.self, forCellWithReuseIdentifier: CardChoiceCell.reuseID)
        collectionView.register(LogTextCell.self, forCellWithReuseIdentifier: LogTextCell.reuseID)
        collectionView.register(
            LogHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: LogHeaderView.reuseID
        )
    }

    private func makeCompositionalLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            guard let self else { return Self.fullWidthSection(height: .estimated(44)) }
            // 从 dataSource 当前 snapshot 取实际 section（iOS 下 snapshot 里 section 比 Mac 少）
            let sections = self.dataSource.snapshot().sectionIdentifiers
            guard sectionIndex < sections.count else {
                return Self.fullWidthSection(height: .estimated(44))
            }
            let section = sections[sectionIndex]
            switch section {
            case .toolbar:
                #if targetEnvironment(macCatalyst)
                return Self.insetSection(Self.fullWidthSection(height: .absolute(52)))
                #else
                let s = Self.fullWidthSection(height: .absolute(60))
                s.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12)
                return s
                #endif
            case .status:
                return Self.insetSection(Self.fullWidthSection(height: .absolute(32)))
            case .chips:
                return self.chipsSection()
            case .inputs:
                return Self.insetSection(Self.fullWidthSection(height: .absolute(44)), spacing: 8)
            case .recommend:
                let s = Self.fullWidthSection(height: .estimated(80))
                s.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16)
                return s
            case .cards:
                return self.cardsSection()
            case .log:
                return self.logSection()
            }
        }
    }

    private static func fullWidthSection(height: NSCollectionLayoutDimension) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: height
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        return NSCollectionLayoutSection(group: group)
    }

    private static func insetSection(
        _ section: NSCollectionLayoutSection,
        spacing: CGFloat = 0
    ) -> NSCollectionLayoutSection {
        section.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        if spacing > 0 {
            section.interGroupSpacing = spacing
        }
        return section
    }

    private func chipsSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .estimated(80),
            heightDimension: .absolute(34)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        #if targetEnvironment(macCatalyst)
        // Mac：wrap 布局，chip 自动换行，不需要横向滚动
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(34)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        group.interItemSpacing = .fixed(8)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 8
        #else
        // iOS：单行横向滚动
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .estimated(900),
            heightDimension: .absolute(34)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        #endif
        section.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        return section
    }

    private func cardsSection() -> NSCollectionLayoutSection {
        #if targetEnvironment(macCatalyst)
        // Mac：三列并排
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / 3.0),
            heightDimension: .absolute(680)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 5)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(680)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 11, bottom: 8, trailing: 11)
        return section
        #else
        // iOS：单卡全宽，分页横滑
        let cardHeight: CGFloat = 620
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(cardHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.88),
            heightDimension: .absolute(cardHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPaging
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20)
        return section
        #endif
    }

    private func logSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(200)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 24, trailing: 16)

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(44)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]
        return section
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, ItemID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return UICollectionViewCell() }
            // 从 snapshot 取实际 section（iOS 下 section 少，rawValue 映射不可靠）
            let sections = self.dataSource.snapshot().sectionIdentifiers
            guard indexPath.section < sections.count else { return UICollectionViewCell() }
            let section = sections[indexPath.section]
            switch section {
            case .toolbar:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ToolbarCell.reuseID, for: indexPath
                ) as! ToolbarCell
                cell.host(self.toolbarContainer)
                return cell
            case .status:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: StatusBarCell.reuseID, for: indexPath
                ) as! StatusBarCell
                cell.host(self.logStatusBar)
                return cell
            case .chips:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ClassChipCell.reuseID, for: indexPath
                ) as! ClassChipCell
                let index = indexPath.item
                cell.configure(
                    title: self.classOptions[index].title,
                    selected: self.selectedClassIndexes.contains(index)
                ) { [weak self] in self?.tapClassChipAtIndex(index) }
                return cell
            case .inputs:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: InputFieldCell.reuseID, for: indexPath
                ) as! InputFieldCell
                let idx = indexPath.item
                cell.configure(
                    placeholder: "第 \(idx + 1) 张牌：中文名 / 英文名 / 卡牌ID",
                    text: self.cardInputTexts[idx]
                ) { [weak self] text in
                    self?.cardInputTexts[idx] = text
                    self?.cardFieldDidChange()
                }
                return cell
            case .recommend:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: RecommendationCell.reuseID, for: indexPath
                ) as! RecommendationCell
                cell.host(self.recommendationPanel)
                return cell
            case .cards:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: CardChoiceCell.reuseID, for: indexPath
                ) as! CardChoiceCell
                let idx = indexPath.item
                if idx < self.currentCardDisplays.count {
                    self.configureCardCell(cell, with: self.currentCardDisplays[idx])
                }
                return cell
            case .log:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: LogTextCell.reuseID, for: indexPath
                ) as! LogTextCell
                cell.host(self.resultView)
                return cell
            }
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self else { return nil }
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: LogHeaderView.reuseID,
                for: indexPath
            ) as! LogHeaderView
            header.configure(expanded: self.isLogExpanded)
            header.onTap = { [weak self] in
                self?.toggleLogExpanded()
            }
            return header
        }
    }

    private func applyInitialSnapshot() {
        applySnapshot(animatingDifferences: false)
    }

    private func applySnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ItemID>()

        snapshot.appendSections([.toolbar])
        snapshot.appendItems([ItemID.toolbar], toSection: .toolbar)

        #if targetEnvironment(macCatalyst)
        snapshot.appendSections([.status])
        snapshot.appendItems([ItemID.status], toSection: .status)
        #endif

        snapshot.appendSections([.chips])
        snapshot.appendItems(classOptions.indices.map { ItemID.chip($0) }, toSection: .chips)

        #if targetEnvironment(macCatalyst)
        snapshot.appendSections([.inputs])
        snapshot.appendItems((0..<cardInputTexts.count).map { ItemID.input($0) }, toSection: .inputs)
        #endif

        snapshot.appendSections([.recommend])
        if showRecommendation {
            snapshot.appendItems([ItemID.recommend], toSection: .recommend)
        }

        snapshot.appendSections([.cards])
        if !currentCardDisplays.isEmpty {
            snapshot.appendItems(currentCardDisplays.indices.map { ItemID.card($0) }, toSection: .cards)
        }

        #if targetEnvironment(macCatalyst)
        snapshot.appendSections([.log])
        if isLogExpanded {
            snapshot.appendItems([ItemID.log], toSection: .log)
        }
        #endif

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    private func toggleLogExpanded() {
        isLogExpanded.toggle()
        applySnapshot(animatingDifferences: true)
    }

    // 用于 diffable data source 的稳定标识
    private enum ItemID: Hashable {
        case toolbar
        case status
        case chip(Int)
        case input(Int)
        case recommend
        case card(Int)
        case log
    }

    private func configureRecommendationPanel() {
        recommendationPanel.backgroundColor = .tertiarySystemBackground
        recommendationPanel.layer.cornerRadius = 14
        recommendationPanel.layer.borderWidth = 1
        recommendationPanel.layer.borderColor = UIColor.separator.cgColor
        recommendationPanel.alpha = 0
        recommendationPanel.isHidden = true

        recommendationTitleLabel.font = .preferredFont(forTextStyle: .headline)
        recommendationTitleLabel.textColor = .label
        recommendationTitleLabel.numberOfLines = 0

        recommendationReasonLabel.font = .preferredFont(forTextStyle: .subheadline)
        recommendationReasonLabel.textColor = .secondaryLabel
        recommendationReasonLabel.numberOfLines = 0

        // 纯 Auto Layout：标题在上，理由在下
        recommendationPanel.addSubview(recommendationTitleLabel)
        recommendationPanel.addSubview(recommendationReasonLabel)
        recommendationTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(16)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        recommendationReasonLabel.snp.makeConstraints { make in
            make.top.equalTo(recommendationTitleLabel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
        }
    }


    private func setToolbarEnabled(_ enabled: Bool) {
        inspectButton.isEnabled = enabled
        refreshButton.isEnabled = enabled
        compareButton.isEnabled = enabled
        guideButton.isEnabled = enabled
        clearButton.isEnabled = enabled
        #if targetEnvironment(macCatalyst)
        logWatcherButton.isEnabled = enabled
        screenshotButton.isEnabled = enabled
        autoWatchButton.isEnabled = enabled
        #endif
    }

    private func bootstrapData() {
        updateStatusBar("正在加载本地缓存...", isActive: false)
        setToolbarEnabled(false)

        Task { [weak self] in
            guard let self else {
                return
            }

            let loadedFromCache = await dataService.loadCachedSnapshot()
            let statuses = await dataService.dataSourceStatuses()
            await MainActor.run {
                self.updateStatusBar(
                    loadedFromCache ? "已加载缓存，后台检查更新..." : "缓存不可用，正在下载数据...",
                    isActive: false
                )
                self.hideDraftPreview()
                self.resultView.text = self.render(statuses)
                self.setToolbarEnabled(true)
            }

            await self.refreshInBackground(cacheWasReady: loadedFromCache)
        }
    }

    private func refreshInBackground(cacheWasReady: Bool) async {
        do {
            try await dataService.refreshAll()
            let statuses = await dataService.dataSourceStatuses()
            await MainActor.run {
                self.updateStatusBar(
                    cacheWasReady ? "后台数据已更新" : "数据下载完成",
                    isActive: false
                )
                if !self.resultView.text.contains("卡牌数据：") {
                    self.hideDraftPreview()
                    self.resultView.text = self.render(statuses)
                }
            }
        } catch {
            await MainActor.run {
                self.updateStatusBar(
                    cacheWasReady ? "后台更新失败，使用缓存" : "数据加载失败",
                    isActive: false
                )
            }
        }
    }

    @objc private func inspectDataSources() {
        updateStatusBar("正在检查数据源...", isActive: false)
        setToolbarEnabled(false)

        Task { [weak self] in
            guard let self else {
                return
            }

            let statuses = await dataService.dataSourceStatuses()
            await MainActor.run {
                self.updateStatusBar("已缓存 \(statuses.filter(\.isCached).count)/\(statuses.count) 个数据集", isActive: false)
                self.hideDraftPreview()
                self.resultView.text = self.render(statuses)
                self.setToolbarEnabled(true)
            }
        }
    }

    @objc private func refreshData() {
        updateStatusBar("正在刷新远程数据...", isActive: false)
        setToolbarEnabled(false)

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await dataService.refreshAll()
                let statuses = await dataService.dataSourceStatuses()
                await MainActor.run {
                    self.updateStatusBar("数据刷新完成", isActive: false)
                    self.hideDraftPreview()
                    self.resultView.text = "数据刷新完成。点击「对比」查看当前三张牌评分。\n\n" + self.render(statuses)
                    self.setToolbarEnabled(true)
                }
            } catch {
                await MainActor.run {
                    self.updateStatusBar("刷新失败", isActive: false)
                    self.hideDraftPreview()
                    self.resultView.text = String(describing: error)
                    self.setToolbarEnabled(true)
                }
            }
        }
    }

    @objc private func compareScores() {
        updateStatusBar("正在对比三张牌得分...", isActive: false)
        setToolbarEnabled(false)

        Task { [weak self] in
            guard let self else {
                return
            }

            let cardIds = self.cardInputTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let arenaClasses = confirmedArenaClasses
            var evaluations: [DraftChoiceEvaluation] = []
            for arenaClass in arenaClasses {
                let evaluation = await dataService.evaluateDraftChoices(
                    cardIds: cardIds,
                    classContext: arenaClass
                )
                evaluations.append(evaluation)
            }
            await MainActor.run {
                self.updateStatusBar("对比完成", isActive: false)
                self.applyRenderedDraftOutput(self.renderDraftOutput(evaluations))
                self.setToolbarEnabled(true)
            }
        }
    }

    @objc private func showSourceGuide() {
        updateStatusBar("平台说明", isActive: false)
        hideDraftPreview()
        resultView.text = renderSourceGuide()
    }

    // 输入框内容变化时，若当前显示的卡片数量与非空输入框数量不符则清空展示
    @objc private func cardFieldDidChange() {
        let filledCount = cardInputTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        if filledCount < currentCardDisplays.count {
            hideDraftPreview()
        }
    }

    @objc private func clearResults() {
        hideDraftPreview()
        cardInputTexts = ["", "", ""]
        #if targetEnvironment(macCatalyst)
        var snap = dataSource.snapshot()
        if snap.sectionIdentifiers.contains(.inputs) {
            let inputItems = snap.itemIdentifiers(inSection: .inputs)
            if !inputItems.isEmpty { snap.reconfigureItems(inputItems); dataSource.apply(snap, animatingDifferences: false) }
        }
        #endif
        resultView.text = ""
        updateStatusBar("已清空", isActive: false)
        UIView.animate(withDuration: 0.18) {
            self.clearButton.alpha = 0.5
        } completion: { _ in
            UIView.animate(withDuration: 0.18) {
                self.clearButton.alpha = 1
            }
        }
    }

    // MARK: - 自动截图监听（Mac 专用）

    #if targetEnvironment(macCatalyst)
    @objc private func toggleAutoWatch() {
        if isAutoWatching {
            Task { [weak self] in
                guard let self else { return }
                await screenshotFolderWatcher.stop()
                await MainActor.run {
                    self.isAutoWatching = false
                    self.draftWindowExpiresAt = nil
                    self.updateAutoWatchButtonStyle(watching: false)
                    self.watchPathsPanel.isHidden = true
                    self.updateStatusBar("自动截图监听已停止", isActive: false)
                }
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await screenshotFolderWatcher.start { [weak self] url in
                await MainActor.run {
                    self?.handleNewScreenshotFile(url)
                }
            }
            await MainActor.run {
                self.isAutoWatching = true
                self.updateAutoWatchButtonStyle(watching: true)
                self.watchPathsPanel.isHidden = false
                self.refreshWatchPathRows()
                self.updateStatusBar("自动截图监听中", isActive: true)
            }
        }
    }

    private func updateAutoWatchButtonStyle(watching: Bool) {
        setToolbarButtonStyle(
            autoWatchButton,
            image: "camera.viewfinder",
            label: watching ? "停止" : "自动",
            activeColor: watching ? .systemOrange : nil
        )
    }

    private func handleNewScreenshotFile(_ url: URL) {
        // 判断是否在选牌窗口期
        let inDraftWindow: Bool
        if isWatchingLogs {
            if let expires = draftWindowExpiresAt, Date() < expires {
                inDraftWindow = true
            } else {
                // 日志监听开着但不在窗口期，静默忽略
                return
            }
        } else {
            // 日志监听未开，来一张跑一次
            inDraftWindow = true
        }

        guard inDraftWindow else { return }
        updateStatusBar("检测到新截图，正在识别...", isActive: true)
        recognizeAndAutoScore(url: url)
    }

    private func recognizeAndAutoScore(url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let candidates = await dataService.repository.recognitionCandidates(for: confirmedArenaClasses)
                let result = try await screenshotRecognizer.recognizeCards(from: url, candidates: candidates)
                await MainActor.run {
                    self.applyScreenshotRecognition(result)
                }
            } catch {
                await MainActor.run {
                    self.updateStatusBar("自动识别失败：\(error.localizedDescription)", isActive: true)
                }
            }
        }
    }
    #endif

    private func autoRunScores() {
        updateStatusBar("自动识别完成，正在评分...", isActive: true)

        Task { [weak self] in
            guard let self else { return }
            let cardIds = self.cardInputTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !cardIds.isEmpty else { return }
            let arenaClasses = confirmedArenaClasses
            var evaluations: [DraftChoiceEvaluation] = []
            for arenaClass in arenaClasses {
                let evaluation = await dataService.evaluateDraftChoices(cardIds: cardIds, classContext: arenaClass)
                evaluations.append(evaluation)
            }
            await MainActor.run {
                self.updateStatusBar("自动评分完成", isActive: true)
                self.applyRenderedDraftOutput(self.renderDraftOutput(evaluations))
            }
        }
    }

    #if targetEnvironment(macCatalyst)
    @objc private func toggleLogWatcher() {
        if isWatchingLogs {
            Task { [weak self] in
                guard let self else {
                    return
                }
                await logWatcher.stop()
                await MainActor.run {
                    self.isWatchingLogs = false
                    self.updateLogWatcherButtonStyle(watching: false)
                    self.updateStatusBar("日志监听已停止", isActive: false)
                    self.appendResult("\n\n日志监听已停止。")
                }
            }
            return
        }

        updateStatusBar("正在启动日志监听...", isActive: false)
        logWatcherButton.isEnabled = false
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await logWatcher.ensureLogConfig()
            } catch {
                await MainActor.run {
                    self.updateStatusBar("日志配置检查失败：\(error.localizedDescription)", isActive: false)
                    self.logWatcherButton.isEnabled = true
                }
                return
            }

            await logWatcher.start { [weak self] event in
                await MainActor.run {
                    self?.handleLogEvent(event)
                }
            }
            let status = await logWatcher.status()
            await MainActor.run {
                self.isWatchingLogs = true
                self.logWatcherButton.isEnabled = true
                self.updateLogWatcherButtonStyle(watching: true)
                self.updateStatusBar("日志监听中", isActive: true)
                self.hideDraftPreview()
                self.resultView.text = self.renderLogStatus(status)
            }
        }
    }

    private func updateLogWatcherButtonStyle(watching: Bool) {
        setToolbarButtonStyle(
            logWatcherButton,
            image: watching ? "eye.slash" : "eye",
            label: watching ? "停止" : "监听",
            activeColor: watching ? .systemGreen : nil
        )
    }

    @objc private func importScreenshot() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        let delegate = DraftScreenshotPickerDelegate(
            onPick: { [weak self] url in
                self?.recognizeScreenshot(at: url)
            },
            onCancel: { [weak self] in
                self?.updateStatusBar("已取消导入截图", isActive: false)
            }
        )
        screenshotPickerDelegate = delegate
        picker.delegate = delegate
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    #endif

    // MARK: - iOS: 拍照 / 相册

    #if !targetEnvironment(macCatalyst)
    @objc private func takePhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            updateStatusBar("此设备不支持相机", isActive: false)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func pickFromAlbum() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        let delegate = IOSPhotoPickerDelegate { [weak self] image in
            self?.recognizeImage(image)
        } onCancel: { [weak self] in
            self?.updateStatusBar("已取消选图", isActive: false)
        }
        phPickerDelegate = delegate
        picker.delegate = delegate
        present(picker, animated: true)
    }

    private func recognizeImage(_ image: UIImage) {
        updateStatusBar("正在分析图片...", isActive: false)
        hideDraftPreview()
        resultView.text = "正在识别图片中的卡牌..."
        Task { [weak self] in
            guard let self else { return }
            do {
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                guard let data = image.jpegData(compressionQuality: 0.92) else {
                    throw DraftScreenshotRecognitionError.unreadableImage
                }
                try data.write(to: tmpURL)
                defer { try? FileManager.default.removeItem(at: tmpURL) }
                let candidates = await dataService.repository.recognitionCandidates(for: confirmedArenaClasses)
                let result = try await screenshotRecognizer.recognizeCards(from: tmpURL, candidates: candidates)
                await MainActor.run { self.applyScreenshotRecognition(result) }
            } catch {
                await MainActor.run {
                    self.updateStatusBar("图片识别失败", isActive: false)
                    self.resultView.text = "图片识别失败：\(error.localizedDescription)"
                }
            }
        }
    }
    #endif

    private func recognizeScreenshot(at url: URL) {
        updateStatusBar("正在分析截图...", isActive: false)
        hideDraftPreview()
        resultView.text = "已导入截图：\(url.path)\n正在进入截图识别模块..."

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let candidates = await dataService.repository.recognitionCandidates(for: confirmedArenaClasses)
                let result = try await screenshotRecognizer.recognizeCards(from: url, candidates: candidates)
                await MainActor.run {
                    self.applyScreenshotRecognition(result)
                }
            } catch {
                await MainActor.run {
                    self.updateStatusBar("截图识别失败", isActive: false)
                    self.resultView.text = "截图识别失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func applyScreenshotRecognition(_ result: DraftScreenshotRecognitionResult) {
        let recognizedSlotCount = result.recognizedCardIdSlots.filter { $0 != nil }.count

        if result.recognizedCardIdSlots.isEmpty {
            for (index, cardId) in result.recognizedCardIds.prefix(3).enumerated() {
                cardInputTexts[index] = cardId
            }
        } else {
            for (index, cardId) in result.recognizedCardIdSlots.prefix(3).enumerated() {
                cardInputTexts[index] = cardId ?? ""
            }
        }

        #if targetEnvironment(macCatalyst)
        var snap = dataSource.snapshot()
        if snap.sectionIdentifiers.contains(.inputs) {
            let inputItems = snap.itemIdentifiers(inSection: .inputs)
            if !inputItems.isEmpty { snap.reconfigureItems(inputItems); dataSource.apply(snap, animatingDifferences: false) }
        }
        #endif

        guard recognizedSlotCount > 0 else {
            updateStatusBar("截图未识别出卡牌", isActive: false)
            return
        }

        updateStatusBar("识别完成，正在评分...", isActive: false)
        autoRunScores()
    }

    private func configureClassChips() {
        // chip 样式由 ClassChipCell.configure() 在 dequeue 时设置，不需要预先创建 button
    }

    // cell 内部回调，index 已经确定
    private func tapClassChipAtIndex(_ index: Int) {
        if selectedClassIndexes.contains(index) {
            guard selectedClassIndexes.count > 1 else { return }
            selectedClassIndexes.remove(index)
        } else {
            if selectedClassIndexes.count >= 2 {
                if let oldest = selectedClassIndexes.sorted().first {
                    selectedClassIndexes.remove(oldest)
                }
            }
            selectedClassIndexes.insert(index)
        }
        confirmedArenaClasses = selectedClassIndexes.sorted().map { classOptions[$0].arenaClass }
        updateClassChipStyles()
        let names = confirmedArenaClasses.map(localizedClassName).joined(separator: " + ")
        updateStatusBar("职业：\(names)", isActive: false)
    }

    @objc private func tapClassChip(_ sender: UIButton) {
        tapClassChipAtIndex(sender.tag)
    }

    private func updateClassChipStyles() {
        // 通过 reconfigureItems 让 dataSource 重新调用 cellProvider 更新选中态
        var snapshot = dataSource.snapshot()
        let chipItems = snapshot.itemIdentifiers(inSection: .chips)
        if !chipItems.isEmpty {
            snapshot.reconfigureItems(chipItems)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        compareButton.isEnabled = true
    }

    private func selectedClassDisplayName() -> String {
        selectedClassIndexes.sorted().map { classOptions[$0].title }.joined(separator: " + ")
    }

    private struct HearthArenaRecommendation {
        let cardId: String
        let displayName: String
        let averageScore: Double
        let classScores: [(arenaClass: ArenaClass, score: Double)]
    }

    private struct DraftCardDisplayModel {
        let cardId: String
        let name: String
        let metadataSummary: String
        let hearthArenaScore: Double?
        let hearthArenaClassScores: [(arenaClass: ArenaClass, score: Double)]
        let hsReplay: CardMetric?
        let firestone: CardMetric?
        let isRecommended: Bool
    }

    private struct RenderedDraftOutput {
        let text: String
        let highlightedCardId: String?
        let recommendationTitle: String
        let recommendationReason: String
        let cardDisplays: [DraftCardDisplayModel]
    }

    private func renderDraftOutput(_ evaluations: [DraftChoiceEvaluation]) -> RenderedDraftOutput {
        guard !evaluations.isEmpty else {
            return RenderedDraftOutput(
                text: "请先确认职业后再对比。",
                highlightedCardId: nil,
                recommendationTitle: "暂无推荐",
                recommendationReason: "请先确认职业后再对比。",
                cardDisplays: []
            )
        }

        let recommendation = hearthArenaRecommendation(from: evaluations)
        let cardDisplays = draftCardDisplays(from: evaluations, recommendedCardId: recommendation?.cardId)
        var lines: [String] = []
        let recommendationTitle: String
        let recommendationReason: String
        if let recommendation {
            recommendationTitle = "推荐：\(recommendation.displayName)"
            recommendationReason = "HearthArena 综合分 \(formatNumber(recommendation.averageScore))，可用职业分数：\(recommendation.classScores.map { "\(localizedClassName($0.arenaClass)) \(formatNumber($0.score))" }.joined(separator: "，"))"
            lines.append("【推荐】\(recommendation.displayName)（\(recommendation.cardId)）")
            lines.append("结论：优先选择这张牌。")
            lines.append("原因：HearthArena 是当前硬门槛评分源；在已确认职业的可用评分里，这张牌的综合分最高，为 \(formatNumber(recommendation.averageScore))。")
            lines.append("可用职业分数：\(recommendation.classScores.map { "\(localizedClassName($0.arenaClass)) \(formatNumber($0.score))" }.joined(separator: "，"))")
        } else {
            recommendationTitle = "暂无推荐"
            recommendationReason = "三张牌在已确认职业下都没有 HearthArena 评分。"
            lines.append("结论：暂无推荐。")
            lines.append("原因：三张牌在已确认职业下都没有 HearthArena 评分，因此不做强行选择。")
        }
        lines.append("")

        if evaluations.count == 1, let evaluation = evaluations.first {
            lines.append(render(evaluation, recommendedCardId: recommendation?.cardId))
        } else {
            lines.append(evaluations.map { evaluation in
                [
                    "========== \(localizedClassName(evaluation.classContext)) ==========",
                    render(evaluation, recommendedCardId: recommendation?.cardId)
                ].joined(separator: "\n")
            }.joined(separator: "\n"))
        }

        return RenderedDraftOutput(
            text: lines.joined(separator: "\n"),
            highlightedCardId: recommendation?.cardId,
            recommendationTitle: recommendationTitle,
            recommendationReason: recommendationReason,
            cardDisplays: cardDisplays
        )
    }

    private func hearthArenaRecommendation(from evaluations: [DraftChoiceEvaluation]) -> HearthArenaRecommendation? {
        var cardScoresByClass: [String: [ArenaClass: (score: Double, name: String)]] = [:]

        for evaluation in evaluations {
            for choice in evaluation.choices {
                guard let score = choice.hearthArena?.score else {
                    continue
                }
                let name = choice.metadata?.name ?? choice.cardId
                cardScoresByClass[choice.cardId, default: [:]][evaluation.classContext] = (score, name)
            }
        }

        let candidates = cardScoresByClass.compactMap { cardId, scoresByClass -> HearthArenaRecommendation? in
            let classScores = evaluations.compactMap { evaluation -> (arenaClass: ArenaClass, score: Double)? in
                guard let score = scoresByClass[evaluation.classContext]?.score else {
                    return nil
                }
                return (evaluation.classContext, score)
            }
            guard !classScores.isEmpty else {
                return nil
            }

            let average = classScores.map(\.score).reduce(0, +) / Double(classScores.count)
            let name = scoresByClass.values.first?.name ?? cardId
            return HearthArenaRecommendation(
                cardId: cardId,
                displayName: name,
                averageScore: average,
                classScores: classScores
            )
        }

        return candidates.max { left, right in
            if left.averageScore == right.averageScore {
                return left.cardId > right.cardId
            }
            return left.averageScore < right.averageScore
        }
    }

    private func draftCardDisplays(
        from evaluations: [DraftChoiceEvaluation],
        recommendedCardId: String?
    ) -> [DraftCardDisplayModel] {
        // 收集所有出现过的卡（不管有没有 HA 分）
        var cardsById: [String: CardAggregate] = [:]
        var classScoresByCard: [String: [ArenaClass: Double]] = [:]

        for evaluation in evaluations {
            for choice in evaluation.choices {
                cardsById[choice.cardId] = choice
                if let score = choice.hearthArena?.score {
                    classScoresByCard[choice.cardId, default: [:]][evaluation.classContext] = score
                }
            }
        }

        return cardsById.values
            .map { choice -> DraftCardDisplayModel in
                let scoresByClass = classScoresByCard[choice.cardId] ?? [:]
                let classScores = evaluations.compactMap { evaluation -> (arenaClass: ArenaClass, score: Double)? in
                    guard let score = scoresByClass[evaluation.classContext] else { return nil }
                    return (evaluation.classContext, score)
                }
                let average = classScores.isEmpty
                    ? nil
                    : classScores.map(\.score).reduce(0, +) / Double(classScores.count)
                return DraftCardDisplayModel(
                    cardId: choice.cardId,
                    name: choice.metadata?.name ?? choice.cardId,
                    metadataSummary: choice.metadata.map(metadataSummary) ?? "-",
                    hearthArenaScore: average,
                    hearthArenaClassScores: classScores,
                    hsReplay: choice.hsReplay,
                    firestone: choice.firestone,
                    isRecommended: choice.cardId == recommendedCardId
                )
            }
            .sorted { left, right in
                if left.isRecommended != right.isRecommended { return left.isRecommended }
                let ls = left.hearthArenaScore ?? -1
                let rs = right.hearthArenaScore ?? -1
                return ls > rs
            }
    }

    private func render(_ evaluation: DraftChoiceEvaluation, recommendedCardId: String?) -> String {
        var lines: [String] = [
            "职业：\(localizedClassName(evaluation.classContext))",
            ""
        ]

        let unresolved = evaluation.inputResolutions.filter { $0.cardId == nil }
        if !unresolved.isEmpty {
            lines.append("未识别输入：")
            for item in unresolved {
                lines.append("  \(item.input)")
            }
            lines.append("")
        }

        let resolved = evaluation.inputResolutions.filter { $0.cardId != nil }
        if !resolved.isEmpty {
            lines.append("识别结果：")
            for item in resolved {
                let ambiguity = item.isAmbiguous ? "（同名多版本，已自动选择）" : ""
                lines.append("  \(item.input) -> \(item.cardId ?? "-") \(item.matchedName ?? "")\(ambiguity)")
            }
            lines.append("")
        }

        let visibleChoices = evaluation.choices.filter { $0.hearthArena?.score != nil }
        let hiddenChoices = evaluation.choices.filter { $0.hearthArena?.score == nil }

        if !visibleChoices.isEmpty {
            lines.append("卡牌数据：")
        }

        for choice in visibleChoices {
            let prefix = choice.cardId == recommendedCardId ? "【推荐】" : ""
            lines.append("\(prefix)\(choice.cardId)")
            if let name = choice.metadata?.name {
                lines.append("  卡牌名称：\(name)")
            }
            if let metadata = choice.metadata {
                lines.append("  基础信息：\(metadataSummary(metadata))")
            }
            let hearthArenaScore = choice.hearthArena?.score
            lines.append("  HearthArena 平台：竞技场静态评分 \(formatNumber(hearthArenaScore))")
            if let metric = choice.hsReplay {
                lines.append("  HSReplay 平台：选取率 \(formatPercent(metric.pickRate))，入牌胜率 \(formatPercent(metric.includedWinRate))，抽到胜率 \(formatPercent(metric.drawnWinRate))，打出胜率 \(formatPercent(metric.playedWinRate))，样本对局 \(formatInt(metric.sampleSize))\(confidenceNote(metric))")
            } else {
                lines.append("  HSReplay 平台：暂无数据")
            }
            if let metric = choice.firestone {
                lines.append("  Firestone 平台：入牌胜率 \(formatPercent(metric.includedWinRate))，样本对局 \(formatInt(metric.sampleSize))\(confidenceNote(metric))")
            } else {
                lines.append("  Firestone 平台：暂无数据")
            }
            lines.append("")
        }

        if !hiddenChoices.isEmpty {
            let hiddenNames = hiddenChoices.map { choice in
                if let name = choice.metadata?.name {
                    return "\(name)（\(choice.cardId)）"
                }
                return choice.cardId
            }
            lines.append("未展示（缺少 HearthArena 评分）：\(hiddenNames.joined(separator: "，"))")
            lines.append("")
        }

        if visibleChoices.isEmpty {
            lines.append("卡牌数据：本职业下没有卡牌具备 HearthArena 评分，已全部隐藏。")
        }

        return lines.joined(separator: "\n")
    }

    private func applyRenderedDraftOutput(_ output: RenderedDraftOutput) {
        showDraftPreview(output)

        let text = output.text
        let baseFont = resultView.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label
            ]
        )

        if let highlightedCardId = output.highlightedCardId {
            var location = 0
            for line in text.components(separatedBy: "\n") {
                let lineLength = (line as NSString).length
                let lineRange = NSRange(location: location, length: lineLength)
                if line.contains("【推荐】") || line.contains(highlightedCardId) {
                    attributed.addAttributes(
                        [
                            .backgroundColor: UIColor.systemYellow.withAlphaComponent(0.28),
                            .foregroundColor: UIColor.label,
                            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
                        ],
                        range: lineRange
                    )
                }
                location += lineLength + 1
            }
        }

        resultView.attributedText = attributed
    }

    // 把 DraftCardDisplayModel 渲染到 CardChoiceCell（供 dataSource cellProvider 调用）
    private func configureCardCell(_ cell: CardChoiceCell, with model: DraftCardDisplayModel) {
        cell.cardView.onPreviewRequested = { [weak self] url in self?.presentCardPreview(imageURL: url) }
        cell.cardView.configure(
            name: model.name,
            cardId: model.cardId,
            metadata: model.metadataSummary,
            hearthArenaScore: model.hearthArenaScore.map { formatNumber($0) },
            classScores: model.hearthArenaClassScores.map { "\(localizedClassName($0.arenaClass)) \(formatNumber($0.score))" }.joined(separator: " / "),
            hsReplaySummary: metricSummary(model.hsReplay, source: .hsReplay),
            firestoneSummary: metricSummary(model.firestone, source: .firestone),
            isRecommended: model.isRecommended
        )
        cell.cardView.setCardImageURL(cardImageURL(cardId: model.cardId))
    }

    private func showDraftPreview(_ output: RenderedDraftOutput) {
        recommendationTitleLabel.text = output.recommendationTitle
        recommendationReasonLabel.text = output.recommendationReason
        showRecommendation = true
        currentRecommendationTitle = output.recommendationTitle
        currentRecommendationReason = output.recommendationReason
        currentCardDisplays = output.cardDisplays

        applySnapshot(animatingDifferences: true)

        // snapshot apply 是异步完成的，延一帧后滚动确保 layout 已更新
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.currentCardDisplays.isEmpty else { return }
            let sections = self.dataSource.snapshot().sectionIdentifiers
            guard let cardsSectionIndex = sections.firstIndex(of: .cards) else { return }
            let cardsIndexPath = IndexPath(item: 0, section: cardsSectionIndex)
            self.collectionView.scrollToItem(at: cardsIndexPath, at: .top, animated: true)
        }
    }

    private func hideDraftPreview() {
        showRecommendation = false
        currentCardDisplays = []
        currentRecommendationTitle = ""
        currentRecommendationReason = ""
        if dataSource != nil {
            applySnapshot(animatingDifferences: true)
        }
    }


    private func cardImageURL(cardId: String) -> URL? {
        URL(string: "https://art.hearthstonejson.com/v1/render/latest/zhCN/512x/\(cardId).png")
    }

    private func presentCardPreview(imageURL: URL) {
        let preview = CardImagePreviewViewController(imageURL: imageURL)
        preview.modalPresentationStyle = .pageSheet
        present(preview, animated: true)
    }

    private func renderSummary(_ statuses: [DataSourceStatus]) -> String {
        let cached = statuses.filter(\.isCached).count
        return "已缓存数据集：\(cached)/\(statuses.count)\n缓存目录：\(FilePayloadCache.defaultRootURL().path)"
    }

    private func render(_ statuses: [DataSourceStatus]) -> String {
        var lines: [String] = [
            "数据流：",
            "  远程数据 -> 本地文件缓存 -> 数据源解析器 -> 数据仓库 -> 选牌评分",
            "",
            "缓存目录：",
            "  \(FilePayloadCache.defaultRootURL().path)",
            ""
        ]

        if !statuses.contains(where: \.isCached) {
            lines.append("当前还没有本地数据。点击「刷新数据」下载第一份快照。")
            lines.append("")
        }

        for status in statuses {
            lines.append(localizedSourceName(status.name))
            lines.append("  平台作用：\(localizedSourceDetail(status))")
            lines.append("  缓存键：\(status.cacheKey)")
            lines.append("  缓存策略：\(localizedCachePolicy(status.cachePolicy))")
            lines.append("  远程地址：\(status.payloadURL.absoluteString)")
            if let versionURL = status.versionURL {
                lines.append("  版本地址：\(versionURL.absoluteString)")
            }
            lines.append("  是否已缓存：\(status.isCached ? "是" : "否")")
            if let cachedVersion = status.cachedVersion {
                lines.append("  缓存版本：\(cachedVersion)")
            }
            if let cachedAt = status.cachedAt {
                lines.append("  缓存时间：\(formatDate(cachedAt))")
            }
            if let cachedBytes = status.cachedBytes {
                lines.append("  文件大小：\(formatBytes(cachedBytes))")
            }
            lines.append("  本地文件：\(status.payloadPath)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func renderSourceGuide() -> String {
        [
            "平台说明与可靠性",
            "",
            "HearthArena：",
            "  作用：提供竞技场静态评分，偏专家/模型评价，适合作为基础强度判断。",
            "  可靠性：没有样本量问题，但依赖官网/镜像更新；如果牌不在当前竞技场池，可能没有分数。",
            "",
            "HSReplay：",
            "  作用：提供真实对局统计，包括入牌胜率、抽到胜率、打出胜率、样本对局。",
            "  可靠性：样本量足够时很有价值；样本低于 100 时当前会标记低样本，仅供参考。",
            "",
            "Firestone：",
            "  作用：提供 Firestone/ZeroToHeroes 的真实牌组统计，当前主要使用入牌胜率和样本对局。",
            "  可靠性：样本量大时适合作为实际表现参考；低样本同样会被标记。"
        ].joined(separator: "\n")
    }

    #if targetEnvironment(macCatalyst)
    private func handleLogEvent(_ event: DraftInputEvent) {
        let message = renderLogEvent(event)
        updateStatusBar("日志事件：\(localizedLogEventKind(event.kind))", isActive: true)
        appendResult("\n\n\(message)")

        if event.kind == .draftContinued || event.kind == .draftStarted || event.kind == .arenaStarted {
            draftWindowExpiresAt = Date().addingTimeInterval(60)
            if isAutoWatching {
                appendResult("\n下一步：日志已确认进入选牌流程，自动截图监听已就绪（60s 内有效）。请在炉石中截图。")
                updateStatusBar("选牌窗口期已开启，等待截图...", isActive: true)
            } else {
                appendResult("\n下一步：日志已确认进入选牌流程。开启「自动截图」可自动识别，或手动点击「导入截图」。")
            }
        }
    }
    #endif

    private func appendResult(_ text: String) {
        let existing = resultView.text ?? ""
        resultView.text = existing + text
        let bottom = NSRange(location: max((resultView.text as NSString).length - 1, 0), length: 1)
        resultView.scrollRangeToVisible(bottom)
    }

    private func updateStatusBar(_ message: String, isActive: Bool) {
        logStatusIcon.textColor = isActive ? .systemGreen : .systemGray3
        logStatusLabel.text = message
    }

    #if targetEnvironment(macCatalyst)
    private func renderLogStatusSummary(_ status: HearthstoneLogStatus) -> String {
        guard let location = status.location else {
            return status.message
        }

        return [
            status.message,
            "日志目录：\(location.logsDirectory.path)",
            "当前子目录：\(status.activeLogDirectory?.lastPathComponent ?? "-")"
        ].joined(separator: "\n")
    }

    private func renderLogStatus(_ status: HearthstoneLogStatus) -> String {
        var lines = [
            "炉石日志输入模块",
            "",
            "用途：监听炉石运行日志，识别进入竞技场、继续选牌、已经选择的卡牌等状态；当前三张候选牌仍由截图识别模块负责。",
            "",
            "状态：\(status.message)"
        ]

        if let location = status.location {
            lines.append("发现方式：\(location.wasAutoDiscovered ? "自动搜索" : "手动配置")")
            lines.append("Hearthstone 目录：\(location.hearthstoneDirectory?.path ?? "-")")
            lines.append("Logs 目录：\(location.logsDirectory.path)")
            lines.append("log.config：\(location.configFile?.path ?? "-")")
        } else {
            lines.append("默认搜索路径：/Applications/Hearthstone/Logs")
        }

        lines.append("当前日志子目录：\(status.activeLogDirectory?.path ?? "-")")
        lines.append("")
        lines.append("监听文件：")
        if status.watchedFiles.isEmpty {
            lines.append("  暂无。启动炉石后会自动寻找最新日志子目录。")
        } else {
            lines.append(contentsOf: status.watchedFiles.map { "  \($0.lastPathComponent)" })
        }

        if let event = status.lastEvent {
            lines.append("")
            lines.append("最近事件：")
            lines.append(renderLogEvent(event))
        }

        lines.append("")
        lines.append("识别策略：")
        lines.append("  1. 日志捕获 DRAFTING / pick card / deck card 等状态。")
        lines.append("  2. 进入选牌后触发截图识别。")
        lines.append("  3. 截图模块产出三张 cardId 后，复用现有评分逻辑。")

        return lines.joined(separator: "\n")
    }

    private func renderLogEvent(_ event: DraftInputEvent) -> String {
        var lines = [
            "事件：\(localizedLogEventKind(event.kind))",
            "来源：\(URL(fileURLWithPath: event.sourcePath).lastPathComponent):\(event.lineNumber)"
        ]
        if let heroNumber = event.heroNumber {
            lines.append("英雄编号：HERO_\(heroNumber)")
        }
        if let cardId = event.cardId {
            lines.append("卡牌 ID：\(cardId)")
        }
        lines.append("原始日志：\(event.rawLine)")
        return lines.joined(separator: "\n")
    }

    private func localizedLogEventKind(_ kind: DraftInputEventKind) -> String {
        switch kind {
        case .arenaStarted: "新竞技场开始"
        case .draftStarted: "读取选牌牌组"
        case .draftContinued: "进入/继续选牌"
        case .cardPicked: "已经选择卡牌"
        case .deckCardRead: "读取套牌卡牌"
        case .activeDeck: "选牌结束，进入活动套牌"
        case .rewards: "进入奖励页面"
        }
    }
    #endif

    private func formatNumber(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }
        return String(format: "%.1f", value)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }
        return String(format: "%.1f%%", value)
    }

    private func formatInt(_ value: Int?) -> String {
        guard let value else {
            return "-"
        }
        return String(value)
    }

    private func confidenceNote(_ metric: CardMetric) -> String {
        metric.hasReliableSample ? "" : "（低样本，仅供参考）"
    }

    private func metricSummary(_ metric: CardMetric?, source: MetricSource) -> String {
        guard let metric else {
            return "暂无数据"
        }

        switch source {
        case .hearthArena:
            return "评分 \(formatNumber(metric.score))"
        case .hsReplay:
            var lines = [
                "选取率 \(formatPercent(metric.pickRate))",
                "入牌胜率 \(formatPercent(metric.includedWinRate))",
                "抽到胜率 \(formatPercent(metric.drawnWinRate))",
                "打出胜率 \(formatPercent(metric.playedWinRate))",
                "样本 \(formatInt(metric.sampleSize))\(metric.hasReliableSample ? "" : "（低样本）")"
            ]
            return lines.joined(separator: "\n")
        case .firestone:
            return "入牌胜率 \(formatPercent(metric.includedWinRate))\n样本 \(formatInt(metric.sampleSize))\(metric.hasReliableSample ? "" : "（低样本）")"
        }
    }

    private func metadataSummary(_ metadata: CardMetadata) -> String {
        var parts: [String] = []
        if let cost = metadata.cost {
            parts.append("费用 \(cost)")
        }
        if let type = metadata.type {
            parts.append("类型 \(type)")
        }
        if let rarity = metadata.rarity {
            parts.append("稀有度 \(rarity)")
        }
        if let cardClass = metadata.cardClass {
            parts.append("职业 \(localizedClassName(cardClass))")
        }
        return parts.isEmpty ? "-" : parts.joined(separator: "，")
    }

    private func localizedClassName(_ arenaClass: ArenaClass) -> String {
        switch arenaClass {
        case .deathKnight: "死亡骑士"
        case .demonHunter: "恶魔猎手"
        case .druid: "德鲁伊"
        case .hunter: "猎人"
        case .mage: "法师"
        case .paladin: "圣骑士"
        case .priest: "牧师"
        case .rogue: "潜行者"
        case .shaman: "萨满祭司"
        case .warlock: "术士"
        case .warrior: "战士"
        case .neutral: "中立"
        }
    }

    private func localizedSourceName(_ name: String) -> String {
        switch name {
        case "HearthArena tier score":
            return "HearthArena 竞技场评分镜像"
        case "HearthArena official tier page":
            return "HearthArena 官方评分页面"
        case "HearthstoneJSON cards":
            return "HearthstoneJSON 卡牌信息"
        case "Arena rotation":
            return "竞技场轮换信息"
        case "HSReplay card stats":
            return "HSReplay 竞技场卡牌统计"
        case "HSReplay bundle stats":
            return "HSReplay 卡包/礼包统计"
        default:
            if name.hasPrefix("Firestone ") {
                return name.replacingOccurrences(of: "Firestone ", with: "Firestone 职业统计 - ")
            }
            return name
        }
    }

    private func localizedSourceDetail(_ status: DataSourceStatus) -> String {
        switch status.name {
        case "HearthArena tier score":
            return "从 Arena-Tracker 镜像读取 HearthArena 静态分数，按职业和卡牌 ID 匹配。"
        case "HearthArena official tier page":
            return "从 HearthArena 官网页面补充分数，解决镜像缺失卡牌 ID 的问题。"
        case "HearthstoneJSON cards":
            return "官方卡牌元数据，用于中文名/英文名到卡牌 ID 的解析。"
        case "Arena rotation":
            return "当前竞技场赛季和轮换卡池信息。"
        case "HSReplay card stats":
            return "真实对局统计，包含入牌胜率、抽到胜率、打出胜率和样本量。"
        case "HSReplay bundle stats":
            return "卡包/礼包关联统计，后续用于处理特殊选牌包。"
        default:
            if status.name.hasPrefix("Firestone ") {
                return "Firestone/ZeroToHeroes 按职业导出的真实对局统计。"
            }
            return status.detail
        }
    }

    private func localizedCachePolicy(_ policy: String) -> String {
        switch policy {
        case "versioned": "按版本更新"
        case "24h ttl": "24 小时有效"
        default: policy
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private final class DraftCardChoiceView: UIView {
    var representedCardId: String?
    var onPreviewRequested: ((URL) -> Void)?
    private(set) var isMarkedRecommended = false

    // 图片区
    private let imageContainer = UIView()
    private let imageView = UIImageView()
    private let placeholderLabel = UILabel()
    // 角标
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    // 信息区
    private let nameLabel = UILabel()
    private let metadataLabel = UILabel()
    private let scoreLabel = UILabel()       // HA 大分数
    private let scoreTitleLabel = UILabel()  // "HA 评分"
    private let classScoreLabel = UILabel()  // "潜行者 83.0"
    private let divider1 = UIView()
    private let hsTitleLabel = UILabel()      // "HSReplay" 小标题
    private let hsReplayLabel = UILabel()
    private let divider2 = UIView()
    private let fsTitleLabel = UILabel()      // "Firestone" 小标题
    private let firestoneLabel = UILabel()

    private var imageURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

    func configure(
        name: String,
        cardId: String,
        metadata: String,
        hearthArenaScore: String?,
        classScores: String,
        hsReplaySummary: String,
        firestoneSummary: String,
        isRecommended: Bool
    ) {
        representedCardId = cardId
        isMarkedRecommended = isRecommended

        nameLabel.text = name
        metadataLabel.text = metadata
        scoreLabel.text = hearthArenaScore ?? "—"
        classScoreLabel.text = classScores.isEmpty ? "-" : classScores
        hsReplayLabel.text = hsReplaySummary
        firestoneLabel.text = firestoneSummary

        badgeLabel.text = isRecommended ? "★ 推荐" : "候选"

        if isRecommended {
            backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
            layer.borderColor = UIColor.systemBlue.cgColor
            layer.borderWidth = 2
            superview?.layer.shadowOpacity = 0.22
            badgeView.backgroundColor = .systemBlue
            badgeLabel.textColor = .white
            scoreLabel.textColor = .systemBlue
            scoreTitleLabel.textColor = UIColor.systemBlue.withAlphaComponent(0.7)
            nameLabel.textColor = .label
        } else {
            backgroundColor = .secondarySystemBackground
            layer.borderColor = UIColor.separator.cgColor
            layer.borderWidth = 1
            superview?.layer.shadowOpacity = 0.08
            badgeView.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.12)
            badgeLabel.textColor = .secondaryLabel
            scoreLabel.textColor = .label
            scoreTitleLabel.textColor = .tertiaryLabel
            nameLabel.textColor = .label
        }
    }

    func setCardImageURL(_ url: URL?) {
        imageURL = url
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = nil
        imageView.alpha = 0
        placeholderLabel.isHidden = false

        guard let url else {
            placeholderLabel.text = "暂无卡图"
            return
        }
        placeholderLabel.text = "加载中..."
        imageView.sd_setImage(
            with: url,
            placeholderImage: nil,
            options: [.retryFailed, .continueInBackground, .scaleDownLargeImages, .highPriority]
        ) { [weak self] image, _, _, _ in
            guard let self else { return }
            self.placeholderLabel.isHidden = image != nil
            UIView.transition(with: self.imageContainer, duration: 0.25, options: .transitionCrossDissolve) {
                self.imageView.alpha = image == nil ? 0 : 1
            }
        }
    }

    // MARK: - Private

    @objc private func handleImageTap() {
        guard let imageURL else { return }
        UIView.animate(withDuration: 0.1, animations: { self.imageContainer.alpha = 0.8 }) { _ in
            UIView.animate(withDuration: 0.15) { self.imageContainer.alpha = 1 }
        }
        onPreviewRequested?(imageURL)
    }

    private func setupViews() {
        clipsToBounds = true   // 必须 true，配合圆角裁切
        layer.cornerRadius = 16
        // shadow 放到 wrapper 层，这里不做（clipsToBounds=true 会裁掉 shadow）

        imageContainer.layer.cornerRadius = 0   // 上两角圆，下两角直 → 用 maskedCorners
        imageContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        imageContainer.layer.cornerRadius = 16
        imageContainer.clipsToBounds = true
        imageContainer.isUserInteractionEnabled = true
        imageContainer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleImageTap))
        )

        imageView.contentMode = .scaleAspectFit

        placeholderLabel.font = .systemFont(ofSize: 12)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.textAlignment = .center

        badgeView.layer.cornerRadius = 10
        badgeView.clipsToBounds = true
        badgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        badgeLabel.textAlignment = .center
        badgeView.addSubview(badgeLabel)
        badgeLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10))
        }

        nameLabel.font = .systemFont(ofSize: 17, weight: .bold)
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.75

        metadataLabel.font = .systemFont(ofSize: 13)
        metadataLabel.textColor = .tertiaryLabel
        metadataLabel.numberOfLines = 1
        metadataLabel.adjustsFontSizeToFitWidth = true
        metadataLabel.minimumScaleFactor = 0.8

        scoreTitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        scoreTitleLabel.text = "HearthArena"

        scoreLabel.font = .monospacedSystemFont(ofSize: 30, weight: .bold)
        scoreLabel.adjustsFontSizeToFitWidth = true
        scoreLabel.minimumScaleFactor = 0.6

        classScoreLabel.font = .systemFont(ofSize: 13)
        classScoreLabel.textColor = .secondaryLabel
        classScoreLabel.numberOfLines = 2
        classScoreLabel.adjustsFontSizeToFitWidth = true
        classScoreLabel.minimumScaleFactor = 0.8

        for d in [divider1, divider2] { d.backgroundColor = .separator }

        for (label, title) in [(hsTitleLabel, "HSReplay"), (fsTitleLabel, "Firestone")] {
            label.text = title
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .tertiaryLabel
        }

        for label in [hsReplayLabel, firestoneLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
        }
    }

    private func setupLayout() {
        let pad: CGFloat = 12

        addSubview(imageContainer)
        imageContainer.addSubview(imageView)
        imageContainer.addSubview(placeholderLabel)
        addSubview(badgeView)

        imageContainer.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(imageContainer.snp.width).multipliedBy(1.1)
        }
        imageView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        placeholderLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(12)
        }
        badgeView.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(8)
        }

        addSubview(nameLabel)
        addSubview(metadataLabel)
        addSubview(divider2)
        addSubview(scoreTitleLabel)
        addSubview(scoreLabel)
        addSubview(classScoreLabel)
        addSubview(hsTitleLabel)
        addSubview(hsReplayLabel)
        addSubview(fsTitleLabel)
        addSubview(firestoneLabel)

        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(imageContainer.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(pad)
        }
        metadataLabel.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(3)
            make.leading.trailing.equalToSuperview().inset(pad)
        }
        divider2.snp.makeConstraints { make in
            make.top.equalTo(metadataLabel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(pad)
            make.height.equalTo(1)
        }
        scoreTitleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(pad)
            make.lastBaseline.equalTo(scoreLabel.snp.lastBaseline)
        }
        scoreLabel.snp.makeConstraints { make in
            make.top.equalTo(divider2.snp.bottom).offset(6)
            make.leading.equalTo(scoreTitleLabel.snp.trailing).offset(6)
            make.trailing.lessThanOrEqualToSuperview().inset(pad)
        }
        classScoreLabel.snp.makeConstraints { make in
            make.top.equalTo(scoreLabel.snp.bottom).offset(2)
            make.leading.trailing.equalToSuperview().inset(pad)
        }

        #if targetEnvironment(macCatalyst)
        // Mac：HSReplay 和 Firestone 左右两列
        hsTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(classScoreLabel.snp.bottom).offset(8)
            make.leading.equalToSuperview().inset(pad)
        }
        fsTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(hsTitleLabel)
            make.leading.equalTo(self.snp.centerX).offset(5)
            make.trailing.equalToSuperview().inset(pad)
            make.width.equalTo(hsTitleLabel)
        }
        hsReplayLabel.snp.makeConstraints { make in
            make.top.equalTo(hsTitleLabel.snp.bottom).offset(4)
            make.leading.equalToSuperview().inset(pad)
            make.trailing.equalTo(self.snp.centerX).offset(-5)
        }
        firestoneLabel.snp.makeConstraints { make in
            make.top.equalTo(fsTitleLabel.snp.bottom).offset(4)
            make.leading.equalTo(self.snp.centerX).offset(5)
            make.trailing.equalToSuperview().inset(pad)
            make.width.equalTo(hsReplayLabel)
        }
        hsReplayLabel.snp.makeConstraints { make in
            make.bottom.lessThanOrEqualToSuperview().inset(pad)
        }
        firestoneLabel.snp.makeConstraints { make in
            make.bottom.lessThanOrEqualToSuperview().inset(pad)
        }
        #else
        // iOS：HSReplay 和 Firestone 垂直堆叠，充分利用宽屏
        hsTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(classScoreLabel.snp.bottom).offset(8)
            make.leading.equalToSuperview().inset(pad)
        }
        hsReplayLabel.snp.makeConstraints { make in
            make.top.equalTo(hsTitleLabel.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview().inset(pad)
        }
        fsTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(hsReplayLabel.snp.bottom).offset(10)
            make.leading.equalToSuperview().inset(pad)
        }
        firestoneLabel.snp.makeConstraints { make in
            make.top.equalTo(fsTitleLabel.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview().inset(pad)
            make.bottom.lessThanOrEqualToSuperview().inset(pad)
        }
        #endif
    }
}

// MARK: - CollectionView Cells

/// 通用宿主单元格：把外部持有的视图按边距嵌入 contentView，复用时移除以避免重复约束。
private class HostingCollectionViewCell: UICollectionViewCell {
    private weak var hostedView: UIView?
    var hostInsets: UIEdgeInsets { .zero }

    func host(_ view: UIView) {
        guard hostedView !== view else { return }
        hostedView?.removeFromSuperview()
        hostedView = view
        view.removeFromSuperview()
        contentView.addSubview(view)
        view.snp.remakeConstraints { make in
            make.edges.equalToSuperview().inset(hostInsets)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostedView?.removeFromSuperview()
        hostedView = nil
    }
}

private final class ToolbarCell: HostingCollectionViewCell {
    static let reuseID = "ToolbarCell"
}

private final class StatusBarCell: HostingCollectionViewCell {
    static let reuseID = "StatusBarCell"
}

/// Chip cell：内部持有自己的 UIButton，通过 configure() 直接更新，不依赖外部 button 实例复用。
private final class ClassChipCell: UICollectionViewCell {
    static let reuseID = "ClassChipCell"

    private let button = UIButton(type: .system)
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        button.addTarget(self, action: #selector(didTap), for: .touchUpInside)
        button.isUserInteractionEnabled = false // 点击透传到 cell
        contentView.addSubview(button)
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, selected: Bool, onTap: @escaping () -> Void) {
        self.onTap = onTap
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var out = attr; out.font = UIFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular); return out
        }
        cfg.baseBackgroundColor = selected ? .systemBlue : .secondarySystemBackground
        cfg.baseForegroundColor = selected ? .white : .label
        button.configuration = cfg
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        onTap?()
    }

    @objc private func didTap() { onTap?() }
}

/// 输入框 cell：内部持有 UITextField，通过 configure() 更新，不依赖外部实例。
private final class InputFieldCell: UICollectionViewCell, UITextFieldDelegate {
    static let reuseID = "InputFieldCell"
    let textField = UITextField()
    var onTextChange: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        textField.borderStyle = .roundedRect
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        contentView.addSubview(textField)
        textField.snp.makeConstraints { make in make.edges.equalToSuperview() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(placeholder: String, text: String, onTextChange: @escaping (String) -> Void) {
        textField.placeholder = placeholder
        textField.text = text
        self.onTextChange = onTextChange
    }

    @objc private func textChanged() {
        onTextChange?(textField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder(); return true
    }
}

private final class RecommendationCell: HostingCollectionViewCell {
    static let reuseID = "RecommendationCell"
}

/// 卡片 cell：内部持有自己的 DraftCardChoiceView，通过 configure() 更新，不依赖外部实例。
private final class CardChoiceCell: UICollectionViewCell {
    static let reuseID = "CardChoiceCell"
    let cardView = DraftCardChoiceView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in make.edges.equalToSuperview() }
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class LogTextCell: HostingCollectionViewCell {
    static let reuseID = "LogTextCell"
}

/// 日志区可折叠 header：点击切换展开/收起。
private final class LogHeaderView: UICollectionReusableView {
    static let reuseID = "LogHeaderView"

    let titleLabel = UILabel()
    var onTap: (() -> Void)?
    private var expanded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .label
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(expanded: Bool) {
        self.expanded = expanded
        titleLabel.text = expanded ? "▼ 详细日志" : "▶ 详细日志"
    }

    @objc private func handleTap() {
        onTap?()
    }
}

private final class CardImagePreviewViewController: UIViewController, UIGestureRecognizerDelegate {
    private let imageURL: URL
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)

    init(imageURL: URL) {
        self.imageURL = imageURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configure()
        layout()
    }

    private func configure() {
        imageView.contentMode = .scaleAspectFit
        imageView.sd_setImage(
            with: imageURL,
            placeholderImage: nil,
            options: [.retryFailed, .continueInBackground, .scaleDownLargeImages, .highPriority]
        )

        closeButton.setTitle("关闭", for: .normal)
        closeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(close))
        backgroundTap.delegate = self
        view.addGestureRecognizer(backgroundTap)
    }

    private func layout() {
        view.addSubview(imageView)
        view.addSubview(closeButton)

        closeButton.snp.makeConstraints { make in
            make.top.trailing.equalTo(view.safeAreaLayoutGuide).inset(18)
            make.height.equalTo(36)
            make.width.equalTo(64)
        }

        imageView.snp.makeConstraints { make in
            make.top.equalTo(closeButton.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalTo(view.safeAreaLayoutGuide).inset(24)
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else {
            return true
        }
        return !touchedView.isDescendant(of: imageView)
            && !touchedView.isDescendant(of: closeButton)
    }
}

#if targetEnvironment(macCatalyst)
final class FolderPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL) -> Void

    init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        onPick(url)
        if accessing { url.stopAccessingSecurityScopedResource() }
    }
}
#endif

// MARK: - iOS camera delegate

#if !targetEnvironment(macCatalyst)
extension DraftDashboardViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        recognizeImage(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        updateStatusBar("已取消拍照", isActive: false)
    }
}

final class IOSPhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
    private let onPick: (UIImage) -> Void
    private let onCancel: () -> Void

    init(onPick: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else {
            onCancel()
            return
        }
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                if let image {
                    self?.onPick(image)
                } else {
                    self?.onCancel()
                }
            }
        }
    }
}
#endif
