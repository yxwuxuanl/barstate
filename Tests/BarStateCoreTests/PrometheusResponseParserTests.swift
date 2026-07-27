import Foundation
import Testing
@testable import BarStateCore

struct PrometheusResponseParserTests {
    @Test func parsesScalarResult() throws {
        let value = try PrometheusResponseParser.number(from: data(#"""
        {"status":"success","data":{"resultType":"scalar","result":[1720000000.25,"12.5"]}}
        """#))

        #expect(value == 12.5)
    }

    @Test func parsesSingleInstantVector() throws {
        let value = try PrometheusResponseParser.number(from: data(#"""
        {
          "status":"success",
          "data":{
            "resultType":"vector",
            "result":[{"metric":{"job":"api"},"value":[1720000000.25,"0.023"]}]
          }
        }
        """#))

        #expect(value == 0.023)
    }

    @Test func rejectsEmptyInstantVector() {
        #expect(throws: MonitoringError.prometheusEmptyResult) {
            try PrometheusResponseParser.number(from: data(#"""
            {"status":"success","data":{"resultType":"vector","result":[]}}
            """#))
        }
    }

    @Test func rejectsMultipleSeries() {
        #expect(throws: MonitoringError.prometheusMultipleSeries(2)) {
            try PrometheusResponseParser.number(from: data(#"""
            {
              "status":"success",
              "data":{
                "resultType":"vector",
                "result":[
                  {"metric":{"instance":"a"},"value":[1,"1"]},
                  {"metric":{"instance":"b"},"value":[1,"2"]}
                ]
              }
            }
            """#))
        }
    }

    @Test func surfacesPrometheusErrorEnvelope() {
        #expect(throws: MonitoringError.prometheusQueryFailed("bad_data", "invalid parameter")) {
            try PrometheusResponseParser.number(from: data(#"""
            {"status":"error","errorType":"bad_data","error":"invalid parameter"}
            """#))
        }
    }

    @Test func rejectsResponseWithoutPrometheusStatus() {
        #expect(throws: MonitoringError.prometheusQueryFailed(
            "invalid_response",
            L10n.string("error.prometheus_invalid_envelope")
        )) {
            try PrometheusResponseParser.number(from: data(#"""
            {"data":{"resultType":"scalar","result":[1,"1"]}}
            """#))
        }
    }

    @Test func rejectsRangeAndHistogramResults() {
        #expect(throws: MonitoringError.prometheusUnsupportedResultType("matrix")) {
            try PrometheusResponseParser.number(from: data(#"""
            {"status":"success","data":{"resultType":"matrix","result":[]}}
            """#))
        }
        #expect(throws: MonitoringError.prometheusUnsupportedResultType("histogram")) {
            try PrometheusResponseParser.number(from: data(#"""
            {
              "status":"success",
              "data":{"resultType":"vector","result":[{"metric":{},"histogram":[1,{"count":"1"}]}]}
            }
            """#))
        }
    }

    @Test func rejectsNonFiniteSample() {
        #expect(throws: MonitoringError.nonFiniteNumber) {
            try PrometheusResponseParser.number(from: data(#"""
            {"status":"success","data":{"resultType":"scalar","result":[1,"NaN"]}}
            """#))
        }
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}
