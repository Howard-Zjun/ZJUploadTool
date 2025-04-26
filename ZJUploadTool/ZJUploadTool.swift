//
//  ConversationUploadTool.swift
//  ListenSpeak
//
//  Created by ios on 2025/2/25.
//

import UIKit

protocol BaseAudioModel {
        
    var filePath: String? { get set }
    
    var fileURL: String? { get set }
}

/*
 特性：
 1.有音频没有录音会提示
 2.如果音频已经上传就不会再次上传，判断`fileURL`字段
 3.多线程控制
 4.重试
 */
class ZJUploadTool {
    
    struct ConfigModel {
        
        /// 重试次数
        let retryCount: Int
        
        /// 线程上限
        var queueCount: Int
    }
    
    enum ResultType {
        case uploadSuccess
        case uploadFail
        case missAudio
    }
    
    static let shared = ZJUploadTool(config: ConfigModel(retryCount: 3, queueCount: 3))
    
    let semaphore: DispatchSemaphore
    
    let queue = DispatchQueue(label: "\(#file)-\(Date())")
    
    let config: ConfigModel
    
    init(config: ConfigModel) {
        self.config = config
        self.semaphore = DispatchSemaphore(value: config.queueCount)
    }
    
    func upload(audioModels: [BaseAudioModel], uploadIfAudioMiss: Bool, block: @escaping ((ResultType) -> Void)) {
        
        if !uploadIfAudioMiss {
            // 检查音频是否丢失
            for model in audioModels {
                if let filePath = model.filePath {
                    if !FileManager.default.fileExists(atPath: filePath) {
                        block(.missAudio)
                        return
                    }
                } else {
                    block(.missAudio)
                    return
                }
            }
        }
        
        queue.async { [weak self] in
            
            let group = DispatchGroup()
            
            for model in audioModels {
                
                group.enter()
                
                self?.upload(audioModel: model, count: 0) { result in
                    group.leave()
                }
            }
            
            print("[\(#file):\(#line)] \(Thread.current) \(#function) 等待音频上传完毕")
            
            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                print("[\(#file):\(#line)] \(Thread.current) \(#function) 音频上传完毕")
                
                if uploadIfAudioMiss {
                    block(.uploadSuccess)
                } else {
                    for model in audioModels {
                        if model.fileURL == nil {
                            block(.uploadFail)
                            return
                        }
                    }
                    
                    block(.uploadSuccess)
                }
            }
        }
    }
    
    private func upload(audioModel: BaseAudioModel, count: Int, block: @escaping ((ResultType) -> Void)) {
        var audioModel = audioModel
        guard count < config.retryCount else {
            block(.uploadFail)
            return
        }
        
        guard audioModel.fileURL == nil else {
            block(.uploadSuccess)
            return
        }
        
        guard let filePath = audioModel.filePath, FileManager.default.fileExists(atPath: filePath) else {
            block(.missAudio)
            return
        }
        
        semaphore.wait()
        
        let uploadFilePath: String
        let mp3FilePath = filePath.replacingOccurrences(of: ".wav", with: ".mp3")
        if FileManager.default.fileExists(atPath: mp3FilePath) {
            uploadFilePath = mp3FilePath
        } else {
            uploadFilePath = filePath
        }
        
        func fallHandle(Error: Error? = nil) {
            self.semaphore.signal()
            print("[\(#file):\(#line)] \(Thread.current) \(#function) \(uploadFilePath) 上传失败: \(String(describing: Error?.localizedDescription))")

            self.upload(audioModel: audioModel, count: count + 1, block: block)
        }
        
        let task = URLSession.shared.uploadTask(with: <#T##URLRequest#>, from: <#T##Data?#>) { data, response, error in
            guard let data = data,
                    let dict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] else {
                fallHandle(Error: error)
                return
            }
            
            let fileURL = dict["file_url"] as? String
            print("[\(#file):\(#line)] \(Thread.current) \(#function) \(uploadFilePath) 上传成功: \(fileURL ?? "")")
            audioModel.fileURL = fileURL
            
            block(.uploadSuccess)
        }
        task.resume()
    }
}
