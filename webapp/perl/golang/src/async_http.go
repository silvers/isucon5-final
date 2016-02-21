package main

import (
	"bytes"
	"encoding/json"
	// "fmt"
	"io/ioutil"
	"net/http"
	// "net/http/httputil"
	"strings"
	"sync"
)

type Data struct {
	Service string
	Value   string
}

type Req struct {
	Service  string
	Endpoint string
	Method   string
	Headers  string
}

type RequestSlice struct {
	Requests []Req
}

func main() {
	http.HandleFunc("/", handler)
	http.ListenAndServe(":8083", nil)
}

func handler(w http.ResponseWriter, r *http.Request) {
	var requests []Req
	body, _ := ioutil.ReadAll(r.Body)
	json.Unmarshal(body, &requests)

	data := make([]Data, 0, len(requests))

	reciever := parallelReq(requests)

	for {
		res, ok := <-reciever
		if !ok {
			json, _ := json.Marshal(data)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			w.Write(json)
			return
		}
		data = append(data, res)
	}

}

func parallelReq(requests []Req) <-chan Data {

	wg := new(sync.WaitGroup)
	reciever := make(chan Data, 1)

	go func() {
		for i := range requests {
			wg.Add(1)
			req := requests[i]
			request, _ := http.NewRequest("GET", req.Endpoint, nil)
			headers := strings.Split(req.Headers, ",")
			header := strings.Split(headers[0], ":")
			if header[0] != "" {
				request.Header.Set(header[0], header[1])
			}

			go func() {
				defer wg.Done()
				res, _ := http.DefaultClient.Do(request)
				bufbody := new(bytes.Buffer)
				bufbody.ReadFrom(res.Body)
				body := bufbody.String()
				reciever <- Data{req.Service, body}
				res.Body.Close()
			}()
		}
		wg.Wait()
		close(reciever)

	}()

	return reciever
}
