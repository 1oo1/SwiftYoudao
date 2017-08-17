//
//  main.swift
//  YouDaoTranslation
//
//  Created by zc on 2017/8/16.
//  Copyright © 2017年 zc. All rights reserved.
//

import Foundation

enum YouDaoResult: Error {
    case success
    case failure(String)
}

func makeUpUrlString() throws -> URL {
    guard CommandLine.argc > 1 else {
        throw YouDaoResult.failure("参数错误")
    }
    
    let index = Int(arc4random_uniform(11))
    // api 请求参考 https://github.com/liszd/whyliam.workflows.youdao
    // 索性连 key 和下面的 icon 也用了。。。
    let keyFrom = ["whyliam-wf-1", "whyliam-wf-2", "whyliam-wf-3",
                   "whyliam-wf-4", "whyliam-wf-5", "whyliam-wf-6",
                   "whyliam-wf-7", "whyliam-wf-8", "whyliam-wf-9",
                   "whyliam-wf-10", "whyliam-wf-11"][index]
    
    let key = [2002493135, 2002493136, 2002493137,
               2002493138, 2002493139, 2002493140,
               2002493141, 2002493142, 2002493143,
               1947745089, 1947745090][index]
    
    let query = CommandLine.arguments.dropFirst().joined(separator: " ")
    let urlString = "http://fanyi.youdao.com/openapi.do?keyfrom=\(keyFrom)&key=\(String(key))&type=data&doctype=json&version=1.1&q=\(query)"
    guard let encodedStr = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed), let url = URL(string: encodedStr) else {
        throw YouDaoResult.failure("url 构造失败")
    }
    return url
}

func translate(_ url: URL) throws -> [String: Any] {
    var resultError = YouDaoResult.success
    var result: [String: Any] = [:]
    
    let semaphore = DispatchSemaphore(value: 0)
    let task = URLSession(configuration: URLSessionConfiguration.default).dataTask(with: url) { (data, response, error) in
        defer {
            semaphore.signal()
        }
        guard error == nil else {
            resultError = .failure(error!.localizedDescription)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            resultError = .failure("URLResponse -> HTTPURLResponse 失败")
            return
        }
        guard httpResponse.statusCode == 200 else {
            resultError = .failure("有道响应失败:\(httpResponse.statusCode)")
            return
        }
        guard let data = data, let resultDic = (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)) as? [String: Any] else {
            resultError = .failure("数据解析失败")
            return
        }
        guard let errorCode = resultDic["errorCode"] as? Int else {
            resultError = .failure("无 errorCode")
            return
        }
        guard errorCode == 0 else {
            resultError = .failure("YouDao errorCode: \(errorCode)")
            return
        }
        result = resultDic
    }
    task.resume()
    if semaphore.wait(timeout: .now() + 15) == .timedOut {
        task.cancel()
        resultError = .failure("请求超时-15s")
    }
    
    switch resultError {
    case .success:
        return result
    default:
        throw resultError
    }
}

func item(title: String, subTitle: String, arg: String) -> [String: Any] {
    return ["title": title,
            "subtitle": subTitle,
            "arg": arg,
            "icon": ["path": "icon.png"]]
}

func output(items: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: items, options: .prettyPrinted)
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

func parse(result: [String: Any]) -> [[String: Any]] {
    
    func append(to array: inout [[String: Any]], title: String, subTitle: String, arg: String) {
        array.append(item(title: title, subTitle: subTitle, arg: arg))
    }
    
    var items: [[String: Any]] = []
    
    if let basic = result["basic"] as? [String: Any] {
        if let usPhonetic = basic["us-phonetic"] as? String {
            append(to: &items, title: "us:[\(usPhonetic)]", subTitle: "发音", arg: usPhonetic)
        }
        if let ukPhonetic = basic["uk-phonetic"] as? String {
            append(to: &items, title: "uk:[\(ukPhonetic)]", subTitle: "发音", arg: ukPhonetic)
        }
        if let explains = basic["explains"] as? [String] {
            for explain in explains {
                append(to: &items, title: explain, subTitle: "简明释义", arg: explain)
            }
        }
    }
    
    if let translations = result["translation"] as? [String] {
        for translation in translations {
            append(to: &items, title: translation, subTitle: "翻译结果", arg: translation)
        }
    }
    
    if let webs = result["web"] as? [[String: Any]] {
        for web in webs {
            if let key = web["key"] as? String {
                if let values = web["value"] as? [String] {
                    values.forEach({ (v) in
                        append(to: &items, title: v, subTitle: "网络释义 \(key)", arg: v)
                    })
                }
            }
        }
    }
    return items
}

_ = {
    do {
        let url = try makeUpUrlString()
        let result = try translate(url)
        let items = ["items": parse(result: result)]
        output(items: items)
    } catch {
        if let ydError = error as? YouDaoResult, case let .failure(errMsg) = ydError {
            output(items: ["items": item(title: errMsg, subTitle: "查询失败", arg: errMsg)])
        }
    }
}()

