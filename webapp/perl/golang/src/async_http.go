package main

import (
	"encoding/json"
	"log"
	"io"
	"io/ioutil"
	"net/http"
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
	log.Printf("body: %s", body)
	json.Unmarshal(body, &requests)

	data := make([]Data, 0, len(requests))

	reciever := parallelReq(requests)

	for {
		res, ok := <-reciever
		if !ok {
			json, _ := json.Marshal(data)
			log.Printf("json: %s", json)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			w.Write(json)
			return
		}
		data = append(data, res)
	}

}

func parallelReq(requests []Req) <-chan Data {
	wg := &sync.WaitGroup{}
	reciever := make(chan Data, len(requests))

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

			log.Printf("[start] url: %s", req.Endpoint)
			go func() {
				defer wg.Done()
				res, _ := http.DefaultClient.Do(request)
				log.Printf("[end] url: %s [%d] len: %d", req.Endpoint, res.StatusCode, res.ContentLength)
				buf := make([]byte, res.ContentLength)
				io.ReadFull(res.Body, buf)
				body := string(buf)
				res.Body.Close()
				reciever <- Data{req.Service, body}
			}()
		}
		wg.Wait()
		close(reciever)

	}()

	return reciever
}
