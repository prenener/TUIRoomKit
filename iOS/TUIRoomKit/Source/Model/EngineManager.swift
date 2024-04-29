//
//  EngineManager.swift
//  TUIRoomKit
//
//  Created by WesleyLei on 2022/9/22.
//  Copyright © 2022 Tencent. All rights reserved.
//

import Foundation
import TUICore
import RTCRoomEngine
#if TXLiteAVSDK_TRTC
import TXLiteAVSDK_TRTC
#elseif TXLiteAVSDK_Professional
import TXLiteAVSDK_Professional
#endif

class EngineManager: NSObject {
    private static var _shared: EngineManager?
    class func createInstance() -> EngineManager {
        guard let instance = _shared else {
            let engineManager = EngineManager()
            _shared = engineManager
            return engineManager
        }
        return instance
    }
    private(set) lazy var store: RoomStore = {
        let store = RoomStore()
        return store
    }()
    private(set) lazy var roomEngine: TUIRoomEngine = {
        let roomEngine = TUIRoomEngine.sharedInstance()
        roomEngine.addObserver(eventDispatcher)
        roomEngine.getTRTCCloud().addDelegate(observer)
        return roomEngine
    }()
    private lazy var eventDispatcher: RoomEventDispatcher = {
        let eventDispatcher = RoomEventDispatcher()
        return eventDispatcher
    }()
    private lazy var observer: TRTCObserver = {
        let observer = TRTCObserver()
        return observer
    }()
    private let takeSeatTimeOutNumber: Double = 0
    private let openRemoteDeviceTimeOutNumber: Double = 15
    private let rootRouter: RoomRouter = RoomRouter.shared
    private var isLoginEngine: Bool = false
    private let appGroupString: String = "com.tencent.TUIRoomTXReplayKit-Screen"
    
    override private init() {
        super.init()
    }
    
    deinit {
        debugPrint("deinit \(self)")
    }
    
    func setSelfInfo(userName: String, avatarURL: String, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        store.currentUser.userName = userName
        store.currentUser.avatarUrl = avatarURL
        TUIRoomEngine.setSelfInfo(userName: userName, avatarUrl: avatarURL) {
            onSuccess()
        } onError: { code, message in
            onError(code, message)
            debugPrint("---setSelfInfo,code:\(code),message:\(message)")
        }
    }
    
    func createRoom(roomInfo: TUIRoomInfo, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        if !isLoginEngine {
            self.login(sdkAppId: Int(TUILogin.getSdkAppID()), userId: TUILogin.getUserID() ?? "", userSig: TUILogin.getUserSig() ?? "")
            { [weak self] in
                guard let self = self else { return }
                self.isLoginEngine = true
                self.createEngineRoom(roomInfo: roomInfo, onSuccess: onSuccess, onError: onError)
            } onError: { code, message in
                onError(code, message)
            }
        } else {
            createEngineRoom(roomInfo: roomInfo, onSuccess: onSuccess, onError: onError)
        }
    }
    
    func enterRoom(roomId: String, enableAudio: Bool, enableVideo: Bool, isSoundOnSpeaker: Bool,
                   onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        store.videoSetting.isCameraOpened = enableVideo
        store.audioSetting.isSoundOnSpeaker = isSoundOnSpeaker
        setFramework()
        if !isLoginEngine {
            self.login(sdkAppId: Int(TUILogin.getSdkAppID()), userId: TUILogin.getUserID() ?? "", userSig: TUILogin.getUserSig() ?? "")
            { [weak self] in
                guard let self = self else { return }
                self.isLoginEngine = true
                self.enterEngineRoom(roomId: roomId, enableAudio: enableAudio, onSuccess: onSuccess, onError: onError)
            } onError: { code, message in
                onError(code, message)
            }
        } else {
            enterEngineRoom(roomId: roomId, enableAudio: enableAudio, onSuccess: onSuccess, onError: onError)
        }
    }
    
    func exitRoom(onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.exitRoom(syncWaiting: false) { [weak self] in
            guard let self = self else { return }
            self.store.conferenceObserver?.onConferenceExited?(conferenceId: self.store.roomInfo.roomId)
            self.destroyEngineManager()
            EngineEventCenter.shared.notifyUIEvent(key: .TUIRoomKitService_ExitedRoom, param: [:])
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func destroyRoom(onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.destroyRoom { [weak self] in
            guard let self = self else { return }
            self.store.conferenceObserver?.onConferenceFinished?(conferenceId: self.store.roomInfo.roomId)
            self.destroyEngineManager()
            EngineEventCenter.shared.notifyUIEvent(key: .TUIRoomKitService_DestroyedRoom, param: [:])
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func destroyEngineManager() {
        roomEngine.removeObserver(eventDispatcher)
        roomEngine.getTRTCCloud().removeDelegate(observer)
        EngineManager._shared = nil
    }
    
    func muteLocalAudio() {
        roomEngine.muteLocalAudio()
    }
    
    func unmuteLocalAudio(onSuccess:TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.unmuteLocalAudio {
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func openLocalMicrophone(onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        let actionBlock = { [weak self] in
            guard let self = self else { return }
            self.roomEngine.openLocalMicrophone(self.store.audioSetting.audioQuality) { [weak self] in
                guard let self = self else { return }
                self.store.audioSetting.isMicOpened = true
                onSuccess?()
            } onError: { code, message in
                onError?(code, message)
            }
        }
        if RoomCommon.checkAuthorMicStatusIsDenied() {
            actionBlock()
        } else {
            RoomCommon.micStateActionWithPopCompletion { granted in
                if granted {
                    actionBlock()
                }
            }
        }
    }
    
    func closeLocalCamera() {
        store.videoSetting.isCameraOpened = false
        roomEngine.closeLocalCamera()
    }
    
    func openLocalCamera(onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        let actionBlock = { [weak self] in
            guard let self = self else { return }
            self.store.videoSetting.isCameraOpened = true
            self.roomEngine.openLocalCamera(isFront: self.store.videoSetting.isFrontCamera, quality:
                                                self.store.videoSetting.videoQuality) {
                onSuccess?()
            } onError: { code, message in
                onError?(code, message)
            }
        }
        if RoomCommon.checkAuthorCamaraStatusIsDenied() {
            actionBlock()
        } else {
            RoomCommon.cameraStateActionWithPopCompletion { granted in
                if granted {
                    actionBlock()
                }
            }
        }
    }
    
    func switchCamera() {
        store.videoSetting.isFrontCamera = !store.videoSetting.isFrontCamera
        roomEngine.getDeviceManager().switchCamera(store.videoSetting.isFrontCamera)
    }
    
    func switchMirror() {
        store.videoSetting.isMirror = !store.videoSetting.isMirror
        let params = TRTCRenderParams()
        params.mirrorType = store.videoSetting.isMirror ? .enable : .disable
        setLocalRenderParams(params: params)
    }
    
    func muteAllAudioAction(isMute: Bool, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        store.roomInfo.isMicrophoneDisableForAllUser = isMute
        roomEngine.disableDeviceForAllUserByAdmin(device: .microphone, isDisable:
                                                    store.roomInfo.isMicrophoneDisableForAllUser) {
            onSuccess()
        } onError: { code, message in
            onError(code, message)
        }
    }
    
    func muteAllVideoAction(isMute: Bool, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        store.roomInfo.isCameraDisableForAllUser = isMute
        roomEngine.disableDeviceForAllUserByAdmin(device: .camera, isDisable:
                                                    store.roomInfo.isCameraDisableForAllUser) {
            onSuccess()
        } onError: { code, message in
            onError(code, message)
        }
    }
    
    func takeUserOnSeatByAdmin(userId: String, timeout: Double,
                               onAccepted: @escaping TUIRequestAcceptedBlock,
                               onRejected: @escaping TUIRequestRejectedBlock,
                               onCancelled: @escaping TUIRequestCancelledBlock,
                               onTimeout: @escaping TUIRequestTimeoutBlock,
                               onError: @escaping TUIRequestErrorBlock) {
        roomEngine.takeUserOnSeatByAdmin(-1, userId: userId, timeout: timeout) { requestId, userId in
            onAccepted(requestId, userId)
        } onRejected: { requestId, userId, message in
            onRejected( requestId, userId, message)
        } onCancelled: { requestId, userId in
            onCancelled(requestId, userId)
        } onTimeout: { requestId, userId in
            onTimeout(requestId, userId)
        } onError: { requestId, userId, code, message in
            onError(requestId, userId, code, message)
        }
    }
    
    func setAudioRoute(route: TRTCAudioRoute) {
        store.audioSetting.isSoundOnSpeaker = route == .modeSpeakerphone
        roomEngine.getTRTCCloud().setAudioRoute(route)
    }
    
    func takeSeat(onAccepted: TUIRequestAcceptedBlock? = nil,
                  onRejected: TUIRequestRejectedBlock? = nil,
                  onCancelled: TUIRequestCancelledBlock? = nil,
                  onTimeout: TUIRequestTimeoutBlock? = nil,
                  onError: TUIRequestErrorBlock? = nil) -> TUIRequest {
        let request = self.roomEngine.takeSeat(-1, timeout: takeSeatTimeOutNumber) { [weak self] requestId, userId in
            guard let self = self else { return }
            self.store.currentUser.isOnSeat = true
            self.store.selfTakeSeatRequestId = nil
            onAccepted?(requestId, userId)
        } onRejected: { [weak self] requestId, userId, message in
            guard let self = self else { return }
            self.store.selfTakeSeatRequestId = nil
            onRejected?(requestId, userId, message)
        } onCancelled: { [weak self] requestId, userId in
            guard let self = self else { return }
            self.store.selfTakeSeatRequestId = nil
            onCancelled?(requestId, userId)
        } onTimeout: { [weak self] requestId, userId in
            guard let self = self else { return }
            self.store.selfTakeSeatRequestId = nil
            onTimeout?(requestId, userId)
        } onError: { [weak self] requestId, userId, code, message in
            guard let self = self else { return }
            self.store.selfTakeSeatRequestId = nil
            onError?(requestId, userId, code, message)
        }
        store.selfTakeSeatRequestId = request.requestId
        return request
    }
    
    func cancelTakeSeatRequest() {
        guard let requestId = store.selfTakeSeatRequestId else { return }
        cancelRequest(requestId)
        store.selfTakeSeatRequestId = nil
    }
    
    func fetchRoomInfo(onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.fetchRoomInfo { [weak self] roomInfo in
            guard let self = self, let roomInfo = roomInfo else { return }
            self.store.roomInfo = roomInfo
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
            debugPrint("fetchRoomInfo,code:\(code), message:\(message)")
        }
    }
    
    func setLocalRenderParams(params: TRTCRenderParams) {
        roomEngine.getTRTCCloud().setLocalRenderParams(params)
    }
    
    func setGSensorMode(mode: TRTCGSensorMode) {
        roomEngine.getTRTCCloud().setGSensorMode(mode)
    }
    
    func setLocalVideoView(streamType: TUIVideoStreamType, view: UIView?) {
        roomEngine.setLocalVideoView(streamType: streamType, view: view)
    }
    
    func changeUserRole(userId: String, role: TUIRole, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        roomEngine.changeUserRole(userId: userId, role: role, onSuccess: onSuccess, onError: onError)
    }
    
    func responseRemoteRequest(_ requestId: String, agree: Bool, onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.responseRemoteRequest(requestId, agree: agree) {
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func getUserInfo(_ userId: String, onSuccess: @escaping TUIUserInfoBlock, onError: @escaping TUIErrorBlock) {
        roomEngine.getUserInfo(userId, onSuccess: onSuccess, onError: onError)
    }
    
    func stopScreenCapture() {
        roomEngine.stopScreenCapture()
    }
    
    func setVideoEncoderParam(_ param: TRTCVideoEncParam) {
        roomEngine.getTRTCCloud().setVideoEncoderParam(param)
    }
    
    func cancelRequest(_ requestId: String, onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.cancelRequest(requestId) {
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func leaveSeat(onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.leaveSeat {
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func startScreenCapture() {
        roomEngine.startScreenCapture(appGroup: appGroupString)
    }
    
    func stopPlayRemoteVideo(userId: String, streamType: TUIVideoStreamType) {
        roomEngine.stopPlayRemoteVideo(userId: userId, streamType: streamType)
    }
    
    func setRemoteVideoView(userId: String, streamType: TUIVideoStreamType, view: UIView?) {
        roomEngine.setRemoteVideoView(userId: userId, streamType: streamType, view: view)
    }
    
    func startPlayRemoteVideo(userId: String, streamType: TUIVideoStreamType, onSuccess: TUISuccessBlock? = nil,
                              onLoading: TUIPlayOnLoadingBlock? = nil, onError: TUIPlayOnErrorBlock? = nil) {
        roomEngine.startPlayRemoteVideo(userId: userId, streamType: streamType, onPlaying: { _ in
            guard let onSuccess = onSuccess else { return }
            onSuccess()
        }, onLoading: { userId in
            guard let onLoading = onLoading else { return }
            onLoading(userId)
        }, onError: { userId, code, message in
            guard let onError = onError else { return }
            onError(userId, code, message)
        })
    }
    
    func setAudioCaptureVolume(_ captureVolume: Int) {
        store.audioSetting.captureVolume = captureVolume
        roomEngine.getTRTCCloud().setAudioCaptureVolume(captureVolume)
    }
    
    func setAudioPlayoutVolume(_ playVolume: Int) {
        store.audioSetting.playVolume = playVolume
        roomEngine.getTRTCCloud().setAudioPlayoutVolume(playVolume)
    }
    
    func enableAudioVolumeEvaluation(isVolumePrompt: Bool) {
        store.audioSetting.volumePrompt = isVolumePrompt
        if isVolumePrompt {
            roomEngine.getTRTCCloud().enableAudioVolumeEvaluation(300, enable_vad: true)
        } else {
            roomEngine.getTRTCCloud().enableAudioVolumeEvaluation(0, enable_vad: false)
        }
    }
    
    func closeRemoteDeviceByAdmin(userId: String, device: TUIMediaDevice, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        roomEngine.closeRemoteDeviceByAdmin(userId: userId, device: device, onSuccess: onSuccess, onError: onError)
    }
    
    func openRemoteDeviceByAdmin(userId: String, device: TUIMediaDevice,
                                 onAccepted: TUIRequestAcceptedBlock? = nil,
                                 onRejected: TUIRequestRejectedBlock? = nil,
                                 onCancelled: TUIRequestCancelledBlock? = nil,
                                 onTimeout: TUIRequestTimeoutBlock? = nil,
                                 onError: TUIRequestErrorBlock? = nil) {
        roomEngine.openRemoteDeviceByAdmin(userId: userId, device: device, timeout: openRemoteDeviceTimeOutNumber, onAccepted: { requestId, userId in
            onAccepted?(requestId, userId)
        }, onRejected: { requestId, userId, message in
            onRejected?(requestId, userId, message)
        }, onCancelled: { requestId, userId in
            onCancelled?(requestId, userId)
        }, onTimeout: { requestId, userId in
            onTimeout?(requestId, userId)
        }) { requestId, userId, code, message in
            onError?(requestId, userId, code, message)
        }
    }
    
    func disableSendingMessageByAdmin(userId: String, isDisable: Bool, onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.disableSendingMessageByAdmin(userId: userId, isDisable: isDisable) {
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func kickUserOffSeatByAdmin(userId: String, onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.kickUserOffSeatByAdmin(-1, userId: userId) {
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func kickRemoteUserOutOfRoom(userId: String, onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        roomEngine.kickRemoteUserOutOfRoom(userId) {
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func initUserList(onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        self.getUserList(nextSequence: 0, localUserList: []) { [weak self] in
            guard let self = self else { return }
            if self.store.roomInfo.isSeatEnabled {
                self.getSeatList {
                    onSuccess?()
                } onError: { code, message in
                    onError?(code, message)
                }
            } else {
                onSuccess?()
            }
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    func addUserItem(_ userItem: UserEntity) {
        guard getUserItem(userItem.userId) == nil else { return }
        if userItem.userName.isEmpty {
            userItem.userName = userItem.userId
        }
        store.attendeeList.append(userItem)
    }
    
    func deleteUserItem(_ userId: String) {
        store.attendeeList = store.attendeeList.filter({ userItem in
            userItem.userId != userId
        })
    }
    
    func addSeatItem(_ userItem: UserEntity) {
        guard getSeatItem(userItem.userId) == nil else { return }
        store.seatList.append(userItem)
    }
    
    func deleteSeatItem(_ userId: String) {
        store.seatList = store.seatList.filter({ userItem in
            userItem.userId != userId
        })
    }
    
    func updateVideoQuality(quality: TUIVideoQuality) {
        roomEngine.updateVideoQuality(quality)
    }
    
    func enableGravitySensor(enable: Bool) {
        roomEngine.enableGravitySensor(enable: enable)
    }
    
    func setVideoResolutionMode(streamType: TUIVideoStreamType, resolutionMode: TUIResolutionMode) {
        roomEngine.setVideoResolutionMode(streamType: streamType, resolutionMode: resolutionMode)
    }
    
    func changeRaiseHandNoticeState(isShown: Bool) {
        store.isShownRaiseHandNotice = isShown
    }
    
    func setRemoteRenderParams(userId: String, streamType: TRTCVideoStreamType, params: TRTCRenderParams) {
        roomEngine.getTRTCCloud().setRemoteRenderParams(userId, streamType: streamType, params: params)
    }
    
    func updateSeatApplicationList() {
        roomEngine.getSeatApplicationList { [weak self] list in
            guard let self = self else { return }
            self.store.setInviteSeatList(list: list)
        } onError: { code, message in
            debugPrint("getSeatApplicationList,code:\(code),message:\(message)")
        }
    }
}

// MARK: - Private
extension EngineManager {
    private func login(sdkAppId: Int, userId: String, userSig: String, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        V2TIMManager.sharedInstance().initSDK(Int32(sdkAppId), config: V2TIMSDKConfig())
        store.currentUser.userId = userId
        TUIRoomEngine.login(sdkAppId: sdkAppId, userId: userId, userSig: userSig) { [weak self] in
            guard let self = self else { return }
            self.isLoginEngine = true
            onSuccess()
        } onError: { code, message in
            onError(code, message)
        }
    }
    
    private func logout(onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        guard isLoginEngine else { return }
        TUIRoomEngine.logout { [weak self] in
            guard let self = self else { return }
            self.isLoginEngine = false
            onSuccess?()
        } onError: { code, message in
            onError?(code, message)
        }
    }
    
    private func createEngineRoom(roomInfo: TUIRoomInfo, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        guard !store.isEnteredRoom else {
            if store.roomInfo.roomId == roomInfo.roomId {
                RoomVideoFloatView.dismiss()
                onSuccess()
            } else {
                onError(.failed, .inAnotherRoomText)
            }
            return
        }
        self.store.roomInfo = roomInfo
        self.roomEngine.createRoom(roomInfo) {
            onSuccess()
        } onError: { code, message in
            onError(code, message)
        }
    }
    
    private func enterEngineRoom(roomId: String, enableAudio: Bool, onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        guard !store.isEnteredRoom else {
            if store.roomInfo.roomId == roomId {
                RoomVideoFloatView.dismiss()
                EngineEventCenter.shared.notifyUIEvent(key: .TUIRoomKitService_ShowRoomMainView, param: [:])
                onSuccess()
            } else {
                onError(.failed, .inAnotherRoomText)
            }
            return
        }
        roomEngine.enterRoom(roomId) { [weak self] roomInfo in
            guard let self = self else { return }
            guard let roomInfo = roomInfo else { return }
            //Update the room entry data stored
            self.store.roomInfo = roomInfo
            self.store.initialRoomCurrentUser()
            self.store.initalEnterRoomMessage()
            //Initialize user list
            self.initUserList()
            //Initialize video settings
            self.initLocalVideoState()
            if !self.isNeededAutoTakeSeat() {
                self.operateLocalMicrophone(enableAudio: enableAudio)
                onSuccess()
            } else {
                self.autoTakeSeatForOwner { [weak self] in
                    guard let self = self else { return }
                    self.operateLocalMicrophone(enableAudio: enableAudio)
                    onSuccess()
                } onError: { code, message in
                    onError(code, message)
                }
            }
        } onError: { code, message in
            onError(code, message)
        }
    }
    
    private func isNeededAutoTakeSeat() -> Bool {
        return store.roomInfo.isSeatEnabled && store.currentUser.userId == store.roomInfo.ownerId
    }
    
    private func autoTakeSeatForOwner(onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        _ = self.takeSeat() { _,_ in
            onSuccess()
        } onError: { _, _, code, message in
            if code == .alreadyInSeat {
                onSuccess()
            } else {
                onError(code, message)
            }
        }
    }
    
    private func isPushLocalAudioStream(enableAudio: Bool) -> Bool {
        if !enableAudio {
            return false
        }
        if store.roomInfo.isMicrophoneDisableForAllUser, store.currentUser.userId != store.roomInfo.ownerId {
            return false
        }
        if store.roomInfo.isSeatEnabled, store.currentUser.userId != store.roomInfo.ownerId {
            return false
        }
        return true
    }
    
    private func operateLocalMicrophone(enableAudio: Bool ,onSuccess: TUISuccessBlock? = nil, onError: TUIErrorBlock? = nil) {
        if isPushLocalAudioStream(enableAudio: enableAudio) {
            openLocalMicrophone()
        } else if RoomCommon.checkAuthorMicStatusIsDenied() {
            muteLocalAudio()
            openLocalMicrophone()
        }
    }
    
    private func initLocalVideoState() {
        setVideoParam()
        updateVideoQuality(quality: store.videoSetting.videoQuality)
        enableGravitySensor(enable: true)
        setGSensorMode(mode: .uiFixLayout)
        let resolutionMode: TUIResolutionMode = isLandscape ? .landscape : .portrait
        setVideoResolutionMode(streamType: .cameraStream, resolutionMode: resolutionMode)
    }
    
    private func setVideoParam() {
        let param = TRTCVideoEncParam()
        param.videoBitrate = Int32(store.videoSetting.videoBitrate)
        param.videoFps = Int32(store.videoSetting.videoFps)
        param.enableAdjustRes = true
        setVideoEncoderParam(param)
        let params = TRTCRenderParams()
        params.fillMode = .fill
        params.rotation = ._0
        setLocalRenderParams(params: params)
    }
    
    private func getUserList(nextSequence: Int, localUserList: [UserEntity], onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        roomEngine.getUserList(nextSequence: nextSequence) { [weak self] list, nextSequence in
            guard let self = self else { return }
            var localUserList = localUserList
            list.forEach { userInfo in
                if userInfo.userName.isEmpty {
                    userInfo.userName = userInfo.userId
                }
                let userModel = UserEntity()
                userModel.update(userInfo: userInfo)
                localUserList.append(userModel)
            }
            if nextSequence != 0 {
                self.getUserList(nextSequence: nextSequence, localUserList: localUserList, onSuccess: onSuccess, onError: onError)
            } else {
                self.store.attendeeList = localUserList
                onSuccess()
                if !self.store.roomInfo.isSeatEnabled {
                    EngineEventCenter.shared.notifyUIEvent(key: .TUIRoomKitService_RenewVideoSeatView, param: [:])
                }
                EngineEventCenter.shared.notifyUIEvent(key: .TUIRoomKitService_RenewUserList, param: [:])
            }
        } onError: { code, message in
            onError(code, message)
            debugPrint("getUserList:code:\(code),message:\(message)")
        }
    }
    
    private func getSeatList(onSuccess: @escaping TUISuccessBlock, onError: @escaping TUIErrorBlock) {
        roomEngine.getSeatList { [weak self] seatList in
            guard let self = self else { return }
            self.store.initialSeatList(seatList: seatList)
            onSuccess()
        } onError: { code, message in
            onError(code, message)
            debugPrint("getSeatList:code:\(code),message:\(message)")
        }
    }
    
    private func getUserItem(_ userId: String) -> UserEntity? {
        return store.attendeeList.first(where: {$0.userId == userId})
    }
    
    private func getSeatItem(_ userId: String) -> UserEntity? {
        return store.seatList.first(where: { $0.userId == userId })
    }
}
// MARK: - TUIExtensionProtocol

extension EngineManager: TUIExtensionProtocol {
    func getExtensionInfo(_ key: String, param: [AnyHashable: Any]?) -> [AnyHashable: Any] {
        guard let param = param else {
            return [:]
        }
        
        guard let roomId: String = param["roomId"] as? String else {
            return [:]
        }
        
        if key == gRoomEngineKey {
            return [key: roomEngine]
        } else if key == gRoomInfoKey {
            return [key: store.roomInfo]
        } else if key == gLocalUserInfoKey {
            return [key: store.currentUser]
        } else {
            return [:]
        }
    }
}


// MARK: - setFramework
extension EngineManager {
    fileprivate static let TUIRoomKitFrameworkValue = 1
    fileprivate static let TUIRoomKitComponentValue = 18
    fileprivate static let IMComponentValue = 19
    fileprivate static let TUIRoomKitLanguageValue = 3
    private func setFramework() {
        let componentValue = store.isImAccess ? EngineManager.IMComponentValue : EngineManager.TUIRoomKitComponentValue
        let jsonStr = """
            {
                "api":"setFramework",
                "params":{
                    "framework":\(EngineManager.TUIRoomKitFrameworkValue),
                    "component":\(componentValue),
                    "language":\(EngineManager.TUIRoomKitLanguageValue)
                }
            }
        """
        TUIRoomEngine.callExperimentalAPI(jsonStr: jsonStr)
    }
}

private extension String {
    static var inAnotherRoomText: String {
        localized("TUIRoom.in.another.room")
    }
}
