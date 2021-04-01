//
//  EkoCreateCommunityScreenViewModel.swift
//  UpstraUIKit
//
//  Created by Sarawoot Khunsri on 26/8/2563 BE.
//  Copyright © 2563 Upstra. All rights reserved.
//

import UIKit
import EkoChat

#warning("should be renmae to EkoCommunityProfileEditScreenViewModel")
final class EkoCreateCommunityScreenViewModel: EkoCreateCommunityScreenViewModelType {
    
    private let repository: EkoCommunityRepository
    private var communityModeration: EkoCommunityModeration?
    
    private var communityInfoToken: EkoNotificationToken?
    weak var delegate: EkoCreateCommunityScreenViewModelDelegate?
    var addMemberState: EkoCreateCommunityMemberState = .add
    var community: EkoBoxBinding<EkoCommunityModel?> = EkoBoxBinding(nil)
    private var communityId: String = ""
    var storeUsers: [EkoSelectMemberModel] = [] {
        didSet {
            validate()
        }
    }
    private(set) var selectedCategoryId: String? {
        didSet {
            validate()
        }
    }
    
    private var displayName: String = "" {
        didSet {
            validate()
        }
    }
    private var description: String = "" {
        didSet {
            validate()
        }
    }
    private var isPublic: Bool = true {
        didSet {
            validate()
        }
    }
    private var imageAvatar: UIImage? {
        didSet {
            validate()
        }
    }
    
    private var isAdminPost: Bool = true
    private var imageData: EkoImageData?
    
    init() {
        repository = EkoCommunityRepository(client: UpstraUIKitManagerInternal.shared.client)
    }
    
    private var isValueChanged: Bool {
        let isRequiredFieldExisted = !displayName.trimmingCharacters(in: .whitespaces).isEmpty && selectedCategoryId != nil
        
        if let community = community.value {
            // Edit community
            let isValueChanged = (displayName != community.displayName) || (description != community.description) || (community.isPublic != isPublic) || (imageAvatar != nil) || (community.categoryId != selectedCategoryId)
            return isRequiredFieldExisted && isValueChanged
        } else {
            if isPublic {
                // Create public community
                return isRequiredFieldExisted
            } else {
                // Create private community
                return isRequiredFieldExisted && !storeUsers.isEmpty
            }
        }
    }
    
    private func validate() {
        delegate?.screenViewModel(self, state: .validateField(status: isValueChanged))
    }
}

// MARK: - Data Source
extension EkoCreateCommunityScreenViewModel {
    
    func numberOfMemberSelected() -> Int {
        var userCount = storeUsers.count
        if userCount == 0 {
            addMemberState = .add
        } else if userCount < 8 {
            addMemberState = .adding(number: userCount)
        } else {
            addMemberState = .max(number: userCount)
            userCount = 8
        }
        delegate?.screenViewModel(self, state: .updateAddMember)
        return userCount + 1
    }
    
    func user(at indexPath: IndexPath) -> EkoSelectMemberModel? {
        guard !storeUsers.isEmpty, indexPath.item < storeUsers.count else { return nil }
        return storeUsers[indexPath.item]
    }
    
}
// MARK: - Action
extension EkoCreateCommunityScreenViewModel {
    func textFieldEditingChanged(_ textField: EkoTextField) {
        guard let text = textField.text else { return }
        updateDisplayName(text: text)
    }
    
    private func updateDisplayName(text: String) {
        let count = text.utf16.count
        displayName = text
        delegate?.screenViewModel(self, state: .textFieldOnChanged(text: text, lenght: count))
    }
    
    func textViewDidChanged(_ textView: EkoTextView) {
        guard let text = textView.text else { return }
        updateDescription(text: text)
    }
    
    private func updateDescription(text: String) {
        let count = text.utf16.count
        description = text
        delegate?.screenViewModel(self, state: .textViewOnChanged(text: text, lenght: count, hasValue: count > 0))
    }
    
    func text<T>(_ object: T, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if let textField = object as? EkoTextField {
            return textField.verifyFields(shouldChangeCharactersIn: range, replacementString: string)
        } else if let textView = object as? EkoTextView {
            return textView.verifyFields(shouldChangeCharactersIn: range, replacementString: string)
        } else {
            return false
        }
    }

    func selectCommunityType(_ tag: Int) {
        guard let communityType = EkoCreateCommunityTypes(rawValue: tag) else { return }
        isPublic = communityType == .public
        delegate?.screenViewModel(self, state: .selectedCommunityType(type: communityType))
    }
    
    func updateSelectUser(users: [EkoSelectMemberModel]) {
        storeUsers = users
        delegate?.screenViewModel(self, state: .updateAddMember)
    }
    
    func removeUser(at indexPath: IndexPath) {
        storeUsers.remove(at: indexPath.item)
        delegate?.screenViewModel(self, state: .updateAddMember)
    }
    
    func updateSelectedCategory(categoryId: String?) {
        selectedCategoryId = categoryId
    }
    
    func create() {
        let builder = EkoCommunityCreationDataBuilder()
        builder.setDisplayName(displayName)
        builder.setCommunityDescription(description)
        builder.setIsPublic(isPublic)
        
        if !isPublic {
            let userIds = storeUsers.map { $0.userId }
            builder.setUserIds(userIds)
        }
        
        if let selectedCategoryId = selectedCategoryId {
            builder.setCategoryIds([selectedCategoryId])
        }
        
        if imageAvatar != nil {
            uploadAvatar { [weak self] (image) in
                guard let strongSelf = self else { return }
                builder.setAvatar(image)
                strongSelf.repository.createCommunity(builder, completion: {(community, error) in
                    guard let strongSelf = self else { return }
                    
                    if let error = EkoError(error: error), community == nil {
                        strongSelf.delegate?.screenViewModel(strongSelf, failure: error)
                    } else if let community = community {
                        strongSelf.updateRole(withCommunityId: community.communityId)
                    }
                })
            }
        } else {
            repository.createCommunity(builder, completion: { [weak self] (community, error) in
                guard let strongSelf = self else { return }
                
                if let error = EkoError(error: error), community == nil {
                    strongSelf.delegate?.screenViewModel(strongSelf, failure: error)
                } else if let community = community {
                    strongSelf.updateRole(withCommunityId: community.communityId)
                }
            })
        }
    }
    
    func dismiss() {
        delegate?.screenViewModel(self, state: .onDismiss(isChange: isValueChanged))
    }
    
    func getInfo(communityId: String) {
        self.communityId = communityId
        communityInfoToken = repository.getCommunity(withId: communityId).observe{ [weak self] (community, error) in
            guard let object = community.object else { return }
            let model = EkoCommunityModel(object: object)
            self?.community.value = model
            self?.showProfile(model: model)
            if community.dataStatus == .fresh {
                self?.communityInfoToken?.invalidate()
            }
        }
    }
    
    private func showProfile(model: EkoCommunityModel) {
        updateDisplayName(text: model.displayName)
        updateDescription(text: model.description)
        selectedCategoryId = model.categoryId
        isPublic = model.isPublic
        selectCommunityType(model.isPublic ? 0 : 1)
    }
    
    func update() {
        let builder = EkoCommunityUpdateDataBuilder()
        builder.setDisplayName(displayName)
        builder.setCommunityDescription(description)
        builder.setIsPublic(isPublic)
        if let imageData = imageData {
            builder.setAvatar(imageData)
        }
        if let selectedCategoryId = selectedCategoryId {
            builder.setCategoryIds([selectedCategoryId])
        }
        
        if imageAvatar != nil {
            uploadAvatar { [weak self] (image) in
                guard let strongSelf = self else { return }
                builder.setAvatar(image)
                strongSelf.repository.updateCommunity(withId: strongSelf.communityId, builder: builder) { (community, error) in
                    if let error = EkoError(error: error) {
                        EkoHUD.hide()
                        strongSelf.delegate?.screenViewModel(strongSelf, failure: error)
                    } else {
                        strongSelf.delegate?.screenViewModel(strongSelf, state: .updateSuccess)
                    }
                }
            }
        } else {
            repository.updateCommunity(withId: communityId, builder: builder) { [weak self] (community, error) in
                guard let strongSelf = self else { return }
                if let error = EkoError(error: error) {
                    EkoHUD.hide()
                    strongSelf.delegate?.screenViewModel(strongSelf, failure: error)
                } else {
                    strongSelf.delegate?.screenViewModel(strongSelf, state: .updateSuccess)
                }
            }
        }
        
    }
    
    func setImage(for image: UIImage) {
        imageAvatar = image
    }
    
    private func uploadAvatar(completion: @escaping (EkoImageData) -> Void) {
        guard let image = imageAvatar else { return }
        EkoFileService.shared.uploadImage(image: image, progressHandler: { _ in
            
        }) { (result) in
            switch result {
            case .success(let _imageData):
                completion(_imageData)
            case .failure:
                break
            }
        }
    }
}

private extension EkoCreateCommunityScreenViewModel {
    
    // Force set moderator after create the community success
    private func updateRole(withCommunityId communityId: String) {
        let userId = UpstraUIKitManagerInternal.shared.currentUserId
        communityModeration = EkoCommunityModeration(client: UpstraUIKitManagerInternal.shared.client, andCommunity: communityId)
        communityModeration?.addRole(EkoCommunityRole.moderator.rawValue, userIds: [userId]) { [weak self] (success, error) in
            guard let strongSelf = self else { return }
            if let _ = error {
                EkoHUD.hide()
                EkoUtilities.showError()
                return
            } else {
                if success {
                    self?.delegate?.screenViewModel(strongSelf, state: .createSuccess(communityId: communityId))
                } else {
                    EkoHUD.hide()
                    EkoUtilities.showError()
                    return
                }
            }
        }
    }
    
}