import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if !os(Linux)

/// iOS 14 兼容的流式 delegate（替代 URLSession.bytes / AsyncLineSequence）
final class MinisStreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    private var lineHandler: ((String) -> Void)?
    private var completion: ((Error?) -> Void)?
    private var resumed = false
    private let responseCont: CheckedContinuation<HTTPResponse, Error>

    init(responseCont: CheckedContinuation<HTTPResponse, Error>) {
        self.responseCont = responseCont
    }

    func onLine(_ handler: @escaping (String) -> Void) { lineHandler = handler }
    func onFinish(_ handler: @escaping (Error?) -> Void) { completion = handler }

    private func resumeOnce(_ result: Result<HTTPResponse, Error>) {
        guard !resumed else { return }
        resumed = true
        switch result {
        case .success(let r): responseCont.resume(returning: r)
        case .failure(let e): responseCont.resume(throwing: e)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            resumeOnce(.failure(URLError(.badServerResponse)))
            completionHandler(.cancel)
            return
        }
        var headers = [String: String]()
        for (k, v) in http.allHeaderFields {
            if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
        }
        resumeOnce(.success(HTTPResponse(statusCode: http.statusCode, headers: headers)))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let idx = buffer.firstIndex(of: 0x0A) {
            let slice = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            if let line = String(data: Data(slice), encoding: .utf8) {
                lineHandler?(line)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            lineHandler?(line)
            buffer.removeAll()
        }
        completion?(error)
    }
}

/// Adapter that implements HTTPClient protocol using URLSession
public class URLSessionHTTPClientAdapter: HTTPClient {

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func data(for request: HTTPRequest) async throws -> (Data, HTTPResponse) {
        let urlRequest = try createURLRequest(from: request)
        return try await withCheckedThrowingContinuation { cont in
            let task = urlSession.dataTask(with: urlRequest) { data, urlResponse, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let http = urlResponse as? HTTPURLResponse, let data = data else {
                    cont.resume(throwing: URLError(.badServerResponse))
                    return
                }
                var headers = [String: String]()
                for (k, v) in http.allHeaderFields {
                    if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
                }
                cont.resume(returning: (data, HTTPResponse(statusCode: http.statusCode, headers: headers)))
            }
            task.resume()
        }
    }

    public func bytes(for request: HTTPRequest) async throws -> (HTTPByteStream, HTTPResponse) {
        let urlRequest = try createURLRequest(from: request)

        var lineContinuation: AsyncThrowingStream<String, Error>.Continuation!
        let stream = AsyncThrowingStream<String, Error> { continuation in
            lineContinuation = continuation
        }

        let response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HTTPResponse, Error>) in
            let delegate = MinisStreamDelegate(responseCont: cont)
            delegate.onLine { line in lineContinuation.yield(line) }
            delegate.onFinish { error in
                if let error = error {
                    lineContinuation.finish(throwing: error)
                } else {
                    lineContinuation.finish()
                }
            }
            let session = URLSession(configuration: self.urlSession.configuration,
                                     delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: urlRequest)
            // 保持引用，避免被提前释放
            self.retainedSession = session
            self.retainedDelegate = delegate
            self.retainedTask = task
            task.resume()
        }

        return (.lines(stream), response)
    }

    private let urlSession: URLSession
    private var retainedSession: URLSession?
    private var retainedDelegate: MinisStreamDelegate?
    private var retainedTask: URLSessionDataTask?

    /// Converts our HTTPRequest to URLRequest
    private func createURLRequest(from request: HTTPRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }
}
#endif
